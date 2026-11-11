#!/usr/bin/env python3
"""
coverage.py - which implemented instructions do the test programs actually run?

Static coverage is not enough: an instruction can sit in the image and never
retire. This script reuses the reference simulator to execute every program and
records the instructions that actually retired, then reports any implemented
instruction the test suite never touched.

Usage:  python3 tools/coverage.py build/test_alu build/fib ...
"""

import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from iss import Sim, load_hex                      # noqa: E402

# All 37 instructions this core implements, keyed by how they decode.
# key = (opcode, funct3 or None, instr[30] or None)
IMPLEMENTED = {
    (0x33, 0, 0): "add",   (0x33, 0, 1): "sub",   (0x33, 1, 0): "sll",
    (0x33, 2, 0): "slt",   (0x33, 3, 0): "sltu",  (0x33, 4, 0): "xor",
    (0x33, 5, 0): "srl",   (0x33, 5, 1): "sra",   (0x33, 6, 0): "or",
    (0x33, 7, 0): "and",
    (0x13, 0, None): "addi",  (0x13, 2, None): "slti", (0x13, 3, None): "sltiu",
    (0x13, 4, None): "xori",  (0x13, 6, None): "ori",  (0x13, 7, None): "andi",
    (0x13, 1, 0): "slli",     (0x13, 5, 0): "srli",    (0x13, 5, 1): "srai",
    (0x03, 0, None): "lb",  (0x03, 1, None): "lh",  (0x03, 2, None): "lw",
    (0x03, 4, None): "lbu", (0x03, 5, None): "lhu",
    (0x23, 0, None): "sb",  (0x23, 1, None): "sh",  (0x23, 2, None): "sw",
    (0x63, 0, None): "beq", (0x63, 1, None): "bne", (0x63, 4, None): "blt",
    (0x63, 5, None): "bge", (0x63, 6, None): "bltu", (0x63, 7, None): "bgeu",
    (0x6F, None, None): "jal",  (0x67, None, None): "jalr",
    (0x37, None, None): "lui",  (0x17, None, None): "auipc",
}


def classify(instr):
    op = instr & 0x7F
    f3 = (instr >> 12) & 7
    b30 = (instr >> 30) & 1
    for key in ((op, f3, b30), (op, f3, None), (op, None, None)):
        if key in IMPLEMENTED:
            return IMPLEMENTED[key]
    return None


def main():
    bases = sys.argv[1:]
    if not bases:
        print(__doc__)
        sys.exit(1)

    seen = {}
    taken_not_taken = {}          # branch -> set of outcomes observed
    for base in bases:
        imem = load_hex(base + ".hex", 1024)
        dmem = load_hex(base + ".data.hex", 1024)
        sim = Sim(imem, dmem)
        while not sim.halted and sim.error is None and sim.steps < 200000:
            instr = sim.imem[(sim.pc >> 2) % len(sim.imem)]
            pc_before = sim.pc
            name = classify(instr)
            sim.step()
            if name:
                seen.setdefault(name, 0)
                seen[name] += 1
                if name.startswith("b") and name != "bge" or name in (
                        "beq", "bne", "blt", "bge", "bltu", "bgeu"):
                    outcome = "taken" if sim.pc != pc_before + 4 else "not-taken"
                    taken_not_taken.setdefault(name, set()).add(outcome)

    total = len(IMPLEMENTED)
    covered = sorted(seen)
    missing = sorted(set(IMPLEMENTED.values()) - set(seen))

    print(f"instruction coverage: {len(covered)}/{total}")
    print()
    print("  retired counts:")
    for name in sorted(seen, key=lambda n: -seen[n]):
        print(f"    {name:<6} {seen[name]:>6}")
    print()
    print("  branch outcomes (both directions are needed for real coverage):")
    for name in sorted(taken_not_taken):
        outcomes = ", ".join(sorted(taken_not_taken[name]))
        flag = "" if len(taken_not_taken[name]) == 2 else "   <-- only one direction!"
        print(f"    {name:<6} {outcomes}{flag}")
    print()
    if missing:
        print("  NEVER EXECUTED: " + ", ".join(missing))
        sys.exit(1)
    print("  every implemented instruction retired at least once.")


if __name__ == "__main__":
    main()
