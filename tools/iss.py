#!/usr/bin/env python3
"""
iss.py - reference instruction-set simulator for the RV32I subset.

This is the golden model. It is written straight from the RISC-V spec and
shares no code with the Verilog, so when the RTL and this model agree on the
final register file and memory contents, that agreement means something.

It reads the same $readmemh images the Verilog memories read, runs the program
until it parks on a self-loop jump, and writes the expected end state:

    <base>.rexp   32 lines: expected x0..x31
    <base>.mexp   expected data memory words

Usage:
    python3 tools/iss.py build/fib --dmem-words 32 [--trace]
"""

import argparse
import sys

M32 = 0xFFFFFFFF


def s32(v):
    """Interpret a 32-bit pattern as signed."""
    v &= M32
    return v - (1 << 32) if v & 0x80000000 else v


def load_hex(path, words):
    img = [0] * words
    try:
        with open(path) as f:
            i = 0
            for line in f:
                line = line.split("//")[0].strip()
                if not line:
                    continue
                for tok in line.split():
                    if i < words:
                        img[i] = int(tok, 16) & M32
                        i += 1
    except FileNotFoundError:
        pass
    return img


class Sim:
    def __init__(self, imem, dmem):
        self.imem = imem
        self.dmem = dmem          # list of 32-bit words
        self.x = [0] * 32
        self.pc = 0
        self.steps = 0
        self.halted = False
        self.error = None

    # ---- memory helpers (word-organised, byte addressable) ------------------
    def load_word(self, addr):
        return self.dmem[(addr >> 2) % len(self.dmem)]

    def store_bytes(self, addr, value, nbytes):
        idx = (addr >> 2) % len(self.dmem)
        off = addr & 3
        word = self.dmem[idx]
        for k in range(nbytes):
            lane = off + k
            if lane > 3:
                break                      # misaligned: wraps nowhere, drop it
            byte = (value >> (8 * k)) & 0xFF
            word &= ~(0xFF << (8 * lane)) & M32
            word |= byte << (8 * lane)
        self.dmem[idx] = word & M32

    # ---- one instruction ----------------------------------------------------
    def step(self, trace=False):
        instr = self.imem[(self.pc >> 2) % len(self.imem)]
        op = instr & 0x7F
        rd = (instr >> 7) & 0x1F
        f3 = (instr >> 12) & 0x07
        rs1 = (instr >> 15) & 0x1F
        rs2 = (instr >> 20) & 0x1F
        f7 = (instr >> 25) & 0x7F
        b30 = (instr >> 30) & 1

        a = self.x[rs1]
        b = self.x[rs2]

        imm_i = s32(((instr >> 20) & 0xFFF) | (0xFFFFF000 if instr & 0x80000000 else 0))
        imm_s = s32((((instr >> 25) & 0x7F) << 5) | ((instr >> 7) & 0x1F)
                    | (0xFFFFF000 if instr & 0x80000000 else 0))
        imm_b = s32((((instr >> 31) & 1) << 12) | (((instr >> 7) & 1) << 11)
                    | (((instr >> 25) & 0x3F) << 5) | (((instr >> 8) & 0xF) << 1)
                    | (0xFFFFE000 if instr & 0x80000000 else 0))
        imm_u = (instr & 0xFFFFF000) & M32
        imm_j = s32((((instr >> 31) & 1) << 20) | (((instr >> 12) & 0xFF) << 12)
                    | (((instr >> 20) & 1) << 11) | (((instr >> 21) & 0x3FF) << 1)
                    | (0xFFE00000 if instr & 0x80000000 else 0))

        next_pc = (self.pc + 4) & M32
        wb = None                                  # (rd, value)

        if op == 0b0110011:                        # OP  (register-register)
            sh = b & 0x1F
            if f3 == 0b000: r = (a - b) if b30 else (a + b)
            elif f3 == 0b001: r = a << sh
            elif f3 == 0b010: r = 1 if s32(a) < s32(b) else 0
            elif f3 == 0b011: r = 1 if (a & M32) < (b & M32) else 0
            elif f3 == 0b100: r = a ^ b
            elif f3 == 0b101: r = (s32(a) >> sh) if b30 else ((a & M32) >> sh)
            elif f3 == 0b110: r = a | b
            else:             r = a & b
            wb = (rd, r)

        elif op == 0b0010011:                      # OP-IMM
            sh = imm_i & 0x1F
            if f3 == 0b000: r = a + imm_i
            elif f3 == 0b001: r = a << sh
            elif f3 == 0b010: r = 1 if s32(a) < imm_i else 0
            elif f3 == 0b011: r = 1 if (a & M32) < (imm_i & M32) else 0
            elif f3 == 0b100: r = a ^ imm_i
            elif f3 == 0b101: r = (s32(a) >> sh) if b30 else ((a & M32) >> sh)
            elif f3 == 0b110: r = a | imm_i
            else:             r = a & imm_i
            wb = (rd, r)

        elif op == 0b0000011:                      # LOAD
            addr = (a + imm_i) & M32
            word = self.load_word(addr)
            off = addr & 3
            if f3 == 0b000:                        # lb
                v = (word >> (8 * off)) & 0xFF
                r = v - 0x100 if v & 0x80 else v
            elif f3 == 0b100:                      # lbu
                r = (word >> (8 * off)) & 0xFF
            elif f3 == 0b001:                      # lh
                v = (word >> (16 if off & 2 else 0)) & 0xFFFF
                r = v - 0x10000 if v & 0x8000 else v
            elif f3 == 0b101:                      # lhu
                r = (word >> (16 if off & 2 else 0)) & 0xFFFF
            elif f3 == 0b010:                      # lw
                r = word
            else:
                self.error = f"bad load funct3 {f3:03b} at pc={self.pc:#x}"
                return
            wb = (rd, r)

        elif op == 0b0100011:                      # STORE
            addr = (a + imm_s) & M32
            nbytes = {0b000: 1, 0b001: 2, 0b010: 4}.get(f3)
            if nbytes is None:
                self.error = f"bad store funct3 {f3:03b} at pc={self.pc:#x}"
                return
            self.store_bytes(addr, b, nbytes)

        elif op == 0b1100011:                      # BRANCH
            if f3 == 0b000:   taken = (a == b)
            elif f3 == 0b001: taken = (a != b)
            elif f3 == 0b100: taken = (s32(a) < s32(b))
            elif f3 == 0b101: taken = (s32(a) >= s32(b))
            elif f3 == 0b110: taken = ((a & M32) < (b & M32))
            elif f3 == 0b111: taken = ((a & M32) >= (b & M32))
            else:
                self.error = f"reserved branch funct3 {f3:03b} at pc={self.pc:#x}"
                return
            if taken:
                next_pc = (self.pc + imm_b) & M32

        elif op == 0b1101111:                      # JAL
            wb = (rd, (self.pc + 4) & M32)
            next_pc = (self.pc + imm_j) & M32

        elif op == 0b1100111:                      # JALR
            wb = (rd, (self.pc + 4) & M32)
            next_pc = (a + imm_i) & M32 & ~1

        elif op == 0b0110111:                      # LUI
            wb = (rd, imm_u)

        elif op == 0b0010111:                      # AUIPC
            wb = (rd, (self.pc + imm_u) & M32)

        else:
            self.error = f"illegal opcode {op:07b} (instr={instr:08x}) at pc={self.pc:#x}"
            return

        if trace:
            note = "" if wb is None else f" x{wb[0]}<={wb[1] & M32:08x}"
            print(f"{self.pc:08x}: {instr:08x}{note}")

        if wb is not None and wb[0] != 0:
            self.x[wb[0]] = wb[1] & M32

        if next_pc == self.pc:                     # parked on a self-loop
            self.halted = True
        self.pc = next_pc
        self.steps += 1


def main():
    ap = argparse.ArgumentParser(description="RV32I reference simulator")
    ap.add_argument("base", help="base name, e.g. build/fib")
    ap.add_argument("--imem-words", type=int, default=1024)
    ap.add_argument("--dmem-words", type=int, default=1024)
    ap.add_argument("--expect-words", type=int, default=32,
                    help="how many data words to record in the .mexp file")
    ap.add_argument("--max-steps", type=int, default=200000)
    ap.add_argument("--trace", action="store_true")
    args = ap.parse_args()

    imem = load_hex(args.base + ".hex", args.imem_words)
    dmem = load_hex(args.base + ".data.hex", args.dmem_words)

    sim = Sim(imem, dmem)
    while not sim.halted and sim.error is None and sim.steps < args.max_steps:
        sim.step(trace=args.trace)

    if sim.error:
        print(f"iss.py: {sim.error}", file=sys.stderr)
        sys.exit(1)
    if not sim.halted:
        print(f"iss.py: program did not halt within {args.max_steps} steps",
              file=sys.stderr)
        sys.exit(1)

    with open(args.base + ".rexp", "w") as f:
        for v in sim.x:
            f.write(f"{v & M32:08x}\n")
    with open(args.base + ".mexp", "w") as f:
        for i in range(args.expect_words):
            f.write(f"{sim.dmem[i] & M32:08x}\n")

    print(f"iss.py: {args.base} halted after {sim.steps} instructions "
          f"(pc={sim.pc:#010x}); wrote .rexp / .mexp")


if __name__ == "__main__":
    main()
