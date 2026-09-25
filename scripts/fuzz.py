#!/usr/bin/env python3
"""Random differential test: run random RV32I programs on the RTL and on the
reference ISS (rv32i.py) and compare registers + data memory at the end.

    python3 scripts/fuzz.py              # 200 random programs
    python3 scripts/fuzz.py -n 50 -s 7   # 50 programs starting at seed 7
    python3 scripts/fuzz.py --seed 123 --keep   # rerun one, keep build/fuzz.s + build/otter.fst

Programs use only a handful of registers so almost every instruction depends
on a recent one (forwarding / load-use), plus forward branches, jal, jalr
(including odd offsets), and a counted outer loop for backward branches.
Also reads the switches and writes the LEDs (MMIO); the exact sequence of LED
writes must match, so wrong-path stores that leak out are caught.
Register roles: x1-x7 random data, x27 MMIO base, x28 loop counter,
x29 pointer, x30 jalr temp, x31 data base (0x2000).
"""
import argparse
import os
import random
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
from rv32i import ISS, assemble, write_mem, R_OPS, I_OPS, SHIFT_I, LOADS, STORES, BRANCHES

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")
DATA_LO, DATA_HI = 0x2000, 0x2100
MEM_WORDS = DATA_HI // 4
DATA = [f"x{i}" for i in range(1, 8)]


def gen_program(rng, n_slots=120):
    r = lambda: rng.choice(DATA + ["x0"] * (rng.random() < 0.05))
    slots, branches = [], []          # branches: (slot index, target slot index)
    cont = set()                      # 2nd/3rd slot of a unit: never a branch target
    i = 0
    while i < n_slots:
        k = rng.random()
        if k < 0.30:
            op = rng.choice(list(R_OPS))
            slots.append(f"{op} {r()}, {r()}, {r()}")
        elif k < 0.45:
            op = rng.choice(list(I_OPS))
            slots.append(f"{op} {r()}, {r()}, {rng.randint(-2048, 2047)}")
        elif k < 0.50:
            op = rng.choice(list(SHIFT_I))
            slots.append(f"{op} {r()}, {r()}, {rng.randint(0, 31)}")
        elif k < 0.54:
            slots.append(f"{rng.choice(['lui', 'auipc'])} {r()}, {rng.randint(0, 0xFFFFF)}")
        elif k < 0.66:
            op = rng.choice(list(LOADS))
            size = 1 << (LOADS[op] & 3)
            off = rng.randrange(0, DATA_HI - DATA_LO, size)
            if rng.random() < 0.3:    # pointer computed right before use
                slots.append(f"addi x29, x31, {off}")
                cont.add(len(slots))
                slots.append(f"{op} {r()}, 0(x29)")
                i += 1
            else:
                slots.append(f"{op} {r()}, {off}(x31)")
        elif k < 0.76:
            op = rng.choice(list(STORES))
            size = 1 << STORES[op]
            off = rng.randrange(0, DATA_HI - DATA_LO, size)
            if rng.random() < 0.3:
                slots.append(f"addi x29, x31, {off}")
                cont.add(len(slots))
                slots.append(f"{op} {r()}, 0(x29)")
                i += 1
            else:
                slots.append(f"{op} {r()}, {off}(x31)")
        elif k < 0.80:                # MMIO: read switches / write LEDs
            if rng.random() < 0.5:
                slots.append(f"lw {r()}, 0(x27)")
            else:
                slots.append(f"sw {r()}, 32(x27)")
        elif k < 0.92:
            op = rng.choice(list(BRANCHES) + ["jal"])
            branches.append((len(slots), len(slots) + 1 + rng.randint(0, 4)))
            slots.append((op, r(), r()))
        else:                         # auipc x30 ; [addi x30] ; jalr rd, off(x30)
            skip = rng.randint(0, 3)
            odd = rng.random() < 0.3  # jalr must clear bit 0 of the target
            if rng.random() < 0.5:
                slots.append("auipc x30, 0")
                cont.add(len(slots))
                slots.append(f"jalr {r()}, {8 + 4 * skip + odd}(x30)")
                i += 1
            else:
                slots.append("auipc x30, 0")
                cont.update({len(slots), len(slots) + 1})
                slots.append(f"addi x30, x30, {12 + 4 * skip}")
                slots.append(f"jalr {r()}, {int(odd)}(x30)")
                i += 2
            for _ in range(skip):     # skipped filler (should never execute)
                slots.append(f"addi {r()}, {r()}, {rng.randint(-50, 50)}")
                i += 1
        i += 1

    fixed = []
    for b, t in branches:
        while t in cont:
            t += 1
        fixed.append((b, t))
    branches = fixed
    targets = {t for _, t in branches}
    lines = ["li x31, 0x2000", "li x29, 0x2000", "li x27, 0x11000000"]
    lines += [f"li {d}, {rng.randint(-2**31, 2**31 - 1)}" for d in DATA]
    iters = rng.randint(1, 3)
    lines.append(f"li x28, {iters}")
    lines.append("outer:")
    for idx, s in enumerate(slots):
        if idx in targets:
            lines.append(f"L{idx}:")
        if isinstance(s, tuple):
            op, a, b = s
            tgt = dict(branches)[idx]
            lines.append(f"jal {a}, L{tgt}" if op == "jal" else f"{op} {a}, {b}, L{tgt}")
        else:
            lines.append(s)
    for t in targets:
        if t >= len(slots):
            lines.append(f"L{t}:")
    lines += ["addi x28, x28, -1", "bnez x28, outer", "done: j done"]
    return "\n".join(lines) + "\n"


def compile_sim():
    os.makedirs(BUILD, exist_ok=True)
    pkg = "rtl/core/otter_pkg.sv"
    srcs = [pkg] + sorted(
        os.path.join(d, f) for d in ("rtl/core", "rtl/memory", "rtl/io")
        for f in os.listdir(os.path.join(ROOT, d)) if f.endswith(".sv") and f != "otter_pkg.sv")
    subprocess.run(["iverilog", "-g2012", "-Wno-timescale", '-DMEM_FILE="build/fuzz.mem"',
                    "-s", "tb_OTTER_Wrapper", "-o", "build/fuzz.vvp", *srcs,
                    "sim/tb_OTTER_Wrapper.sv", "sim/otter_probe.sv"], cwd=ROOT, check=True,
                   stderr=subprocess.DEVNULL)


def run_one(seed, keep=False):
    rng = random.Random(seed)
    src = gen_program(rng)
    words = assemble(src)
    assert len(words) * 4 < DATA_LO, "program overlaps data region"
    write_mem(os.path.join(BUILD, "fuzz.mem"), words, MEM_WORDS)
    if keep:
        open(os.path.join(BUILD, "fuzz.s"), "w").write(src)

    switches = rng.getrandbits(16)
    iss = ISS(words, io_in=lambda a: switches if a == 0x11000000 else 0)
    steps = 0
    while iss.step():
        steps += 1
    wave = ["-fst", "+WAVE=build/otter.fst"] if keep else ["+NOWAVE"]
    out = subprocess.run(["vvp", "-n", "build/fuzz.vvp", *wave, f"+CYCLES={3 * steps + 100}", "+DUMP", "+VERBOSE", f"+SWITCHES={switches:x}",
                          f"+DUMP_LO={DATA_LO:x}", f"+DUMP_HI={DATA_HI:x}"],
                         cwd=ROOT, capture_output=True, text=True).stdout
    errs = []
    for line in out.splitlines():
        p = line.split()
        if p[:1] == ["REG"]:
            n, v = int(p[1]), p[2]
            if "x" in v or int(v, 16) != iss.x[n]:
                errs.append(f"x{n}: rtl={v} iss={iss.x[n]:08x}")
        elif p[:1] == ["MEM"]:
            a, v = int(p[1], 16), p[2]
            exp = int.from_bytes(iss.mem[a:a + 4], "little")
            if "x" in v or int(v, 16) != exp:
                errs.append(f"mem[{a:04x}]: rtl={v} iss={exp:08x}")
    leds_rtl = [int(l.split()[-1].split("=")[1], 16) for l in out.splitlines()
                if "IO write addr=11000020" in l]
    leds_iss = [v for a, v in iss.io_writes if a == 0x11000020]
    if leds_rtl != leds_iss:
        errs.append(f"LED writes differ: rtl {len(leds_rtl)} writes, iss {len(leds_iss)}; "
                    f"first diff at #{next((i for i, (x, y) in enumerate(zip(leds_rtl, leds_iss)) if x != y), min(len(leds_rtl), len(leds_iss)))}")
    if not any(l.startswith("REG") for l in out.splitlines()):
        errs.append("no state dump from simulation:\n" + out[-500:])
    return src, steps, errs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-n", type=int, default=200, help="number of programs")
    ap.add_argument("-s", "--seed", type=int, default=1, help="first seed")
    ap.add_argument("--keep", action="store_true", help="keep build/fuzz.s (use with -n 1)")
    a = ap.parse_args()
    if a.keep:
        a.n = 1
    compile_sim()
    fails = 0
    for seed in range(a.seed, a.seed + a.n):
        src, steps, errs = run_one(seed, a.keep)
        if errs:
            fails += 1
            path = os.path.join(BUILD, f"fuzz_fail_{seed}.s")
            open(path, "w").write(src)
            print(f"seed {seed}: MISMATCH ({steps} instrs) -> {os.path.relpath(path, ROOT)}")
            for e in errs[:8]:
                print("   ", e)
    print(f"{a.n - fails}/{a.n} programs matched the reference model")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
