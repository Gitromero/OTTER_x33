"""Minimal RV32I assembler + reference instruction-set simulator for OTTER tests.

Assembler syntax: one instruction per line, registers as x0..x31, labels as
`name:`, comments with `#`. Pseudo-ops: nop, li, mv, j, beqz, bnez.
"""
import re

MASK = 0xFFFFFFFF

R_OPS = {  # funct7, funct3
    "add": (0x00, 0), "sub": (0x20, 0), "sll": (0x00, 1), "slt": (0x00, 2),
    "sltu": (0x00, 3), "xor": (0x00, 4), "srl": (0x00, 5), "sra": (0x20, 5),
    "or": (0x00, 6), "and": (0x00, 7),
}
I_OPS = {"addi": 0, "slti": 2, "sltiu": 3, "xori": 4, "ori": 6, "andi": 7}
SHIFT_I = {"slli": (0x00, 1), "srli": (0x00, 5), "srai": (0x20, 5)}
LOADS = {"lb": 0, "lh": 1, "lw": 2, "lbu": 4, "lhu": 5}
STORES = {"sb": 0, "sh": 1, "sw": 2}
BRANCHES = {"beq": 0, "bne": 1, "blt": 4, "bge": 5, "bltu": 6, "bgeu": 7}


def sx(v, bits):
    v &= (1 << bits) - 1
    return v - (1 << bits) if v >> (bits - 1) else v


def reg(t):
    m = re.fullmatch(r"x(\d+)", t)
    if not m or int(m.group(1)) > 31:
        raise ValueError(f"bad register {t!r}")
    return int(m.group(1))


def enc_r(f7, rs2, rs1, f3, rd, op):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def enc_i(imm, rs1, f3, rd, op):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def enc_s(imm, rs2, rs1, f3, op):
    imm &= 0xFFF
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((imm & 0x1F) << 7) | op


def enc_b(imm, rs2, rs1, f3):
    imm &= 0x1FFF
    return (((imm >> 12) & 1) << 31) | (((imm >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) \
        | (f3 << 12) | (((imm >> 1) & 0xF) << 8) | (((imm >> 11) & 1) << 7) | 0x63


def enc_j(imm, rd):
    imm &= 0x1FFFFF
    return (((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3FF) << 21) | (((imm >> 11) & 1) << 20) \
        | (((imm >> 12) & 0xFF) << 12) | (rd << 7) | 0x6F


def _expand(op, args):
    """Expand pseudo-instructions into real ones."""
    if op == "nop":
        return [("addi", ["x0", "x0", "0"])]
    if op == "mv":
        return [("addi", [args[0], args[1], "0"])]
    if op == "j":
        return [("jal", ["x0", args[0]])]
    if op == "beqz":
        return [("beq", [args[0], "x0", args[1]])]
    if op == "bnez":
        return [("bne", [args[0], "x0", args[1]])]
    if op == "li":
        v = int(args[1], 0) & MASK
        if sx(v, 32) == sx(v, 12):
            return [("addi", [args[0], "x0", str(sx(v, 12))])]
        lo = sx(v, 12)
        hi = ((v - lo) >> 12) & 0xFFFFF
        return [("lui", [args[0], str(hi)]), ("addi", [args[0], args[0], str(lo)])]
    return [(op, args)]


def assemble(text, base=0):
    """Assemble source text; returns a list of 32-bit words starting at `base`."""
    insts, labels = [], {}
    for line in text.splitlines():
        line = line.split("#")[0].strip()
        while ":" in line:
            name, line = line.split(":", 1)
            labels[name.strip()] = base + 4 * len(insts)
            line = line.strip()
        if not line:
            continue
        op, _, rest = line.partition(" ")
        args = [a.strip() for a in re.split(r"[,()]", rest) if a.strip()]
        insts.extend(_expand(op.lower(), args))

    def val(t, pc):
        return labels[t] - pc if t in labels else int(t, 0)

    words = []
    for i, (op, a) in enumerate(insts):
        pc = base + 4 * i
        if op in R_OPS:
            f7, f3 = R_OPS[op]
            w = enc_r(f7, reg(a[2]), reg(a[1]), f3, reg(a[0]), 0x33)
        elif op in I_OPS:
            w = enc_i(int(a[2], 0), reg(a[1]), I_OPS[op], reg(a[0]), 0x13)
        elif op in SHIFT_I:
            f7, f3 = SHIFT_I[op]
            w = enc_r(f7, int(a[2], 0) & 0x1F, reg(a[1]), f3, reg(a[0]), 0x13)
        elif op in LOADS:      # lw rd, imm(rs1)
            w = enc_i(int(a[1], 0), reg(a[2]), LOADS[op], reg(a[0]), 0x03)
        elif op in STORES:     # sw rs2, imm(rs1)
            w = enc_s(int(a[1], 0), reg(a[0]), reg(a[2]), STORES[op], 0x23)
        elif op in BRANCHES:
            w = enc_b(val(a[2], pc), reg(a[1]), reg(a[0]), BRANCHES[op])
        elif op == "jal":
            w = enc_j(val(a[1], pc), reg(a[0]))
        elif op == "jalr":     # jalr rd, imm(rs1)
            w = enc_i(int(a[1], 0), reg(a[2]), 0, reg(a[0]), 0x67)
        elif op == "lui":
            w = ((int(a[1], 0) & 0xFFFFF) << 12) | (reg(a[0]) << 7) | 0x37
        elif op == "auipc":
            w = ((int(a[1], 0) & 0xFFFFF) << 12) | (reg(a[0]) << 7) | 0x17
        else:
            raise ValueError(f"unknown instruction {op!r}")
        words.append(w)
    return words


def write_mem(path, words, size_words):
    """Write a $readmemh file, zero-padded to size_words."""
    words = list(words) + [0] * (size_words - len(words))
    with open(path, "w") as f:
        f.write("\n".join(f"{w:08x}" for w in words) + "\n")


class ISS:
    """Reference RV32I model. MMIO (>= 0x10000) stores are recorded in io_writes;
    MMIO loads return the whole 32-bit io_in(addr) word, like the OTTER memory."""

    def __init__(self, words, mem_bytes=0x10000, io_in=lambda addr: 0):
        self.x = [0] * 32
        self.pc = 0
        self.mem = bytearray(mem_bytes)
        for i, w in enumerate(words):
            self.mem[4 * i:4 * i + 4] = w.to_bytes(4, "little")
        self.io_writes = []
        self.io_in = io_in

    def load(self, addr, n, signed):
        if addr >= 0x10000:
            return self.io_in(addr) & MASK
        v = int.from_bytes(self.mem[addr:addr + n], "little")
        return sx(v, 8 * n) & MASK if signed else v

    def step(self):
        """Execute one instruction; returns False on a `j .` self-loop."""
        ir = int.from_bytes(self.mem[self.pc:self.pc + 4], "little")
        op, rd, f3 = ir & 0x7F, (ir >> 7) & 0x1F, (ir >> 12) & 7
        rs1, rs2, f7 = self.x[(ir >> 15) & 0x1F], self.x[(ir >> 20) & 0x1F], ir >> 25
        i_imm = sx(ir >> 20, 12)
        s_imm = sx(((ir >> 25) << 5) | ((ir >> 7) & 0x1F), 12)
        b_imm = sx((((ir >> 31) & 1) << 12) | (((ir >> 7) & 1) << 11)
                   | (((ir >> 25) & 0x3F) << 5) | (((ir >> 8) & 0xF) << 1), 13)
        j_imm = sx((((ir >> 31) & 1) << 20) | (((ir >> 12) & 0xFF) << 12)
                   | (((ir >> 20) & 1) << 11) | (((ir >> 21) & 0x3FF) << 1), 21)
        next_pc, wb = self.pc + 4, None

        def alu(f3, a, b, alt):
            sh = b & 0x1F
            return [
                (a - b) if alt else (a + b), a << sh,
                int(sx(a, 32) < sx(b, 32)), int(a < b), a ^ b,
                (sx(a, 32) >> sh) if alt else (a >> sh), a | b, a & b,
            ][f3] & MASK

        if op == 0x33:
            wb = alu(f3, rs1, rs2, f7 == 0x20)
        elif op == 0x13:
            wb = alu(f3, rs1, i_imm & MASK, f3 == 5 and f7 == 0x20)
        elif op == 0x37:
            wb = ir & 0xFFFFF000
        elif op == 0x17:
            wb = (self.pc + (ir & 0xFFFFF000)) & MASK
        elif op == 0x6F:
            if j_imm == 0:
                return False
            wb, next_pc = self.pc + 4, (self.pc + j_imm) & MASK
        elif op == 0x67:
            wb, next_pc = self.pc + 4, (rs1 + i_imm) & MASK & ~1
        elif op == 0x63:
            taken = [rs1 == rs2, rs1 != rs2, None, None, sx(rs1, 32) < sx(rs2, 32),
                     sx(rs1, 32) >= sx(rs2, 32), rs1 < rs2, rs1 >= rs2][f3]
            if taken:
                next_pc = (self.pc + b_imm) & MASK
        elif op == 0x03:
            addr = (rs1 + i_imm) & MASK
            wb = self.load(addr, 1 << (f3 & 3), not f3 & 4)
        elif op == 0x23:
            addr, n = (rs1 + s_imm) & MASK, 1 << f3
            if addr >= 0x10000:
                self.io_writes.append((addr, rs2))
            else:
                self.mem[addr:addr + n] = (rs2 & ((1 << 8 * n) - 1)).to_bytes(n, "little")
        else:
            raise ValueError(f"unsupported instruction {ir:08x} at {self.pc:x}")
        if wb is not None and rd:
            self.x[rd] = wb
        self.pc = next_pc
        return True

    def run(self, max_steps=100000):
        for _ in range(max_steps):
            if not self.step():
                return
        raise RuntimeError("program did not reach its final `j .`")
