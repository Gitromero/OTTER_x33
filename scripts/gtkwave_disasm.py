#!/usr/bin/env python3
"""GTKWave "Translate Filter Process": turns 32-bit instruction words into
assembly text. GTKWave writes one value per line (in the trace's radix) and
reads one line back. sim/otter.gtkw applies it to the *_ir probe signals; to
use it on another signal: right-click > Data Format > Translate Filter Process
> Enable and Select > scripts/gtkwave_disasm.py.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rv32i import disasm


def translate(v):
    v = v.strip()
    if not v or any(c in v.lower() for c in "xz"):
        return v
    try:
        w = int(v, 2) if len(v) == 32 and set(v) <= {"0", "1"} else int(v, 16)
    except ValueError:
        return v
    return "--" if w == 0 else disasm(w)


for line in sys.stdin:
    sys.stdout.write(translate(line) + "\n")
    sys.stdout.flush()
