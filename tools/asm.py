#!/usr/bin/env python3
"""
asm.py - a small RISC-V assembler for the instruction subset this core supports.

Why write our own instead of using RARS?
  * No Java / GUI needed, so `make` can rebuild every program automatically.
  * It emits exactly the $readmemh format the Verilog memories expect.
  * It also emits a .lst listing (address / machine code / source), which is
    the single most useful artefact when debugging a waveform.

Usage:
    python3 tools/asm.py programs/fib.s -o build/fib
  produces
    build/fib.hex        instruction memory image  (one 32-bit word per line)
    build/fib.data.hex   data memory image         (only if a .data section exists)
    build/fib.lst        human-readable listing

Supported: the full RV32I set implemented by the core
    add sub sll slt sltu xor srl sra or and
    addi slti sltiu xori ori andi slli srli srai
    lb lh lw lbu lhu   sb sh sw
    beq bne blt bge bltu bgeu
    jal jalr lui auipc
plus the usual pseudo-instructions (li, mv, nop, j, ret, beqz, ...).
"""

import re
import sys
import argparse

# ---------------------------------------------------------------- registers --
REGS = {f"x{i}": i for i in range(32)}
REGS.update({
    "zero": 0, "ra": 1, "sp": 2, "gp": 3, "tp": 4,
    "t0": 5, "t1": 6, "t2": 7,
    "s0": 8, "fp": 8, "s1": 9,
    "a0": 10, "a1": 11, "a2": 12, "a3": 13,
    "a4": 14, "a5": 15, "a6": 16, "a7": 17,
    "s2": 18, "s3": 19, "s4": 20, "s5": 21, "s6": 22, "s7": 23,
    "s8": 24, "s9": 25, "s10": 26, "s11": 27,
    "t3": 28, "t4": 29, "t5": 30, "t6": 31,
})

# opcode, funct3, funct7  per mnemonic
R_TYPE = {
    "add":  (0b0110011, 0b000, 0b0000000),
    "sub":  (0b0110011, 0b000, 0b0100000),
    "sll":  (0b0110011, 0b001, 0b0000000),
    "slt":  (0b0110011, 0b010, 0b0000000),
    "sltu": (0b0110011, 0b011, 0b0000000),
    "xor":  (0b0110011, 0b100, 0b0000000),
    "srl":  (0b0110011, 0b101, 0b0000000),
    "sra":  (0b0110011, 0b101, 0b0100000),
    "or":   (0b0110011, 0b110, 0b0000000),
    "and":  (0b0110011, 0b111, 0b0000000),
}
I_ARITH = {
    "addi":  (0b0010011, 0b000),
    "slti":  (0b0010011, 0b010),
    "sltiu": (0b0010011, 0b011),
    "xori":  (0b0010011, 0b100),
    "ori":   (0b0010011, 0b110),
    "andi":  (0b0010011, 0b111),
}
I_SHIFT = {                      # shamt in imm[4:0], funct7 fixed
    "slli": (0b0010011, 0b001, 0b0000000),
    "srli": (0b0010011, 0b101, 0b0000000),
    "srai": (0b0010011, 0b101, 0b0100000),
}
LOADS  = {"lb": 0b000, "lh": 0b001, "lw": 0b010, "lbu": 0b100, "lhu": 0b101}
STORES = {"sb": 0b000, "sh": 0b001, "sw": 0b010}
BRANCH = {"beq": 0b000, "bne": 0b001, "blt": 0b100,
          "bge": 0b101, "bltu": 0b110, "bgeu": 0b111}


class AsmError(Exception):
    pass


def reg(tok, line_no):
    t = tok.strip().lower()
    if t not in REGS:
        raise AsmError(f"line {line_no}: unknown register '{tok}'")
    return REGS[t]


def parse_int(tok, line_no):
    t = tok.strip()
    try:
        if t.lower().startswith("0x") or t.lower().startswith("-0x"):
            return int(t, 16)
        if t.lower().startswith("0b") or t.lower().startswith("-0b"):
            return int(t, 2)
        return int(t, 10)
    except ValueError:
        raise AsmError(f"line {line_no}: cannot parse number '{tok}'")


def fits_signed(value, bits):
    lo, hi = -(1 << (bits - 1)), (1 << (bits - 1)) - 1
    return lo <= value <= hi


def mask(value, bits):
    return value & ((1 << bits) - 1)


# ----------------------------------------------------------- field encoders --
def enc_r(op, f3, f7, rd, rs1, rs2):
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def enc_i(op, f3, rd, rs1, imm):
    return (mask(imm, 12) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def enc_s(op, f3, rs1, rs2, imm):
    i = mask(imm, 12)
    return (((i >> 5) & 0x7F) << 25) | (rs2 << 20) | (rs1 << 15) | \
           (f3 << 12) | ((i & 0x1F) << 7) | op


def enc_b(op, f3, rs1, rs2, imm):
    i = mask(imm, 13)
    return (((i >> 12) & 1) << 31) | (((i >> 5) & 0x3F) << 25) | (rs2 << 20) | \
           (rs1 << 15) | (f3 << 12) | (((i >> 1) & 0xF) << 8) | \
           (((i >> 11) & 1) << 7) | op


def enc_u(op, rd, imm20):
    return (mask(imm20, 20) << 12) | (rd << 7) | op


def enc_j(op, rd, imm):
    i = mask(imm, 21)
    return (((i >> 20) & 1) << 31) | (((i >> 1) & 0x3FF) << 21) | \
           (((i >> 11) & 1) << 20) | (((i >> 12) & 0xFF) << 12) | (rd << 7) | op


# -------------------------------------------------------- pseudo expansion ---
def split_operands(text):
    return [t.strip() for t in text.split(",")] if text.strip() else []


MEM_RE = re.compile(r"^\s*(-?\w+|-?0x[0-9a-fA-F]+)?\s*\(\s*(\w+)\s*\)\s*$")


def parse_mem(tok, line_no):
    """Parse `offset(reg)`, `(reg)` or a bare `reg`."""
    m = MEM_RE.match(tok)
    if m:
        off = m.group(1)
        return (0 if off is None else off), m.group(2)
    raise AsmError(f"line {line_no}: expected offset(reg), got '{tok}'")


def li_sequence(rd, value):
    """Return the instruction words for `li rd, value`."""
    value &= 0xFFFFFFFF
    low = value & 0xFFF
    simm12 = low - 0x1000 if low & 0x800 else low
    if fits_signed(value if value < 0x80000000 else value - (1 << 32), 12):
        v = value if value < 0x80000000 else value - (1 << 32)
        return [enc_i(0b0010011, 0b000, rd, 0, v)]
    # lui takes the top 20 bits, corrected for the sign-extension that the
    # following addi will perform.
    upper = (value - simm12) >> 12 & 0xFFFFF
    seq = [enc_u(0b0110111, rd, upper)]
    if simm12 != 0:
        seq.append(enc_i(0b0010011, 0b000, rd, rd, simm12))
    return seq


def pseudo_size(mnem, ops, labels_known, line_no):
    """How many 32-bit words this (possibly pseudo) instruction occupies.

    Pass 1 must agree with pass 2 exactly, or every later label is wrong. So
    `li` asks the *same* function that will emit it, and `la` is always two
    words (lui+addi) so that a forward reference cannot change the size.
    """
    if mnem == "la":
        return 2
    if mnem == "li":
        if len(ops) != 2:
            raise AsmError(f"line {line_no}: li needs rd, imm")
        return len(li_sequence(0, parse_int(ops[1], line_no)))
    return 1


PSEUDOS = {
    "nop", "li", "la", "mv", "not", "neg", "seqz", "snez", "sltz", "sgtz",
    "j", "jr", "ret", "call", "beqz", "bnez", "blez", "bgez", "bltz", "bgtz",
    "bgt", "ble", "bgtu", "bleu",
}


# --------------------------------------------------------------- assembler ---
class Assembler:
    def __init__(self):
        self.labels = {}
        self.text = []        # list of (addr, word, source_line, line_no)
        self.data = []        # list of (addr, word)

    # ---- pass 0: tokenise ------------------------------------------------
    def tokenise(self, src):
        out = []
        for line_no, raw in enumerate(src.splitlines(), start=1):
            line = raw.split("#")[0].split("//")[0]
            if ";" in line:
                line = line.split(";")[0]
            line = line.strip()
            if not line:
                continue
            # one or more leading labels
            while True:
                m = re.match(r"^([A-Za-z_.$][\w.$]*)\s*:\s*(.*)$", line)
                if not m:
                    break
                out.append(("label", m.group(1), line_no, raw))
                line = m.group(2).strip()
                if not line:
                    break
            if not line:
                continue
            parts = line.split(None, 1)
            mnem = parts[0].lower()
            rest = parts[1] if len(parts) > 1 else ""
            if mnem.startswith("."):
                out.append(("dir", (mnem, rest), line_no, raw))
            else:
                out.append(("insn", (mnem, rest), line_no, raw))
        return out

    # ---- pass 1: addresses -------------------------------------------------
    def layout(self, toks):
        section = "text"
        addr = {"text": 0, "data": 0}
        for kind, payload, line_no, raw in toks:
            if kind == "label":
                self.labels[payload] = addr[section]
            elif kind == "dir":
                name, rest = payload
                if name in (".text", ".data"):
                    section = name[1:]
                elif name == ".word":
                    n = len(split_operands(rest))
                    addr[section] += 4 * n
                elif name == ".space":
                    nbytes = parse_int(rest, line_no)
                    if nbytes % 4:
                        raise AsmError(f"line {line_no}: .space must be a multiple of 4")
                    addr[section] += nbytes
                elif name in (".globl", ".global", ".align", ".org"):
                    if name == ".org":
                        addr[section] = parse_int(rest, line_no)
                else:
                    raise AsmError(f"line {line_no}: unknown directive '{name}'")
            else:
                mnem, rest = payload
                if section != "text":
                    raise AsmError(f"line {line_no}: instruction in .data section")
                n = pseudo_size(mnem, split_operands(rest), self.labels, line_no)
                addr["text"] += 4 * n
        return addr

    # ---- pass 2: emit --------------------------------------------------------
    def emit(self, toks):
        section = "text"
        pc = 0
        dptr = 0
        for kind, payload, line_no, raw in toks:
            if kind == "label":
                continue
            if kind == "dir":
                name, rest = payload
                if name in (".text", ".data"):
                    section = name[1:]
                elif name == ".word":
                    for tok in split_operands(rest):
                        tok = tok.strip()
                        if tok in self.labels:
                            v = self.labels[tok]
                        else:
                            v = parse_int(tok, line_no)
                        if section == "data":
                            self.data.append((dptr, v & 0xFFFFFFFF))
                            dptr += 4
                        else:
                            self.text.append((pc, v & 0xFFFFFFFF, raw.strip(), line_no))
                            pc += 4
                elif name == ".space":
                    nbytes = parse_int(rest, line_no)
                    for _ in range(nbytes // 4):
                        if section == "data":
                            self.data.append((dptr, 0)); dptr += 4
                        else:
                            self.text.append((pc, 0, raw.strip(), line_no)); pc += 4
                elif name == ".org":
                    if section == "data":
                        dptr = parse_int(rest, line_no)
                    else:
                        pc = parse_int(rest, line_no)
                continue

            mnem, rest = payload
            ops = split_operands(rest)
            words = self.encode(mnem, ops, pc, line_no)
            for w in words:
                self.text.append((pc, w & 0xFFFFFFFF, raw.strip(), line_no))
                pc += 4

    # ---- the encoder ---------------------------------------------------------
    def label_or_int(self, tok, line_no):
        t = tok.strip()
        if t in self.labels:
            return self.labels[t]
        return parse_int(t, line_no)

    def encode(self, mnem, ops, pc, line_no):
        m = mnem
        E = lambda msg: AsmError(f"line {line_no}: {msg}")

        # ---------------- pseudo-instructions -> real ones -------------------
        if m == "nop":
            return [enc_i(0b0010011, 0b000, 0, 0, 0)]
        if m == "li":
            if len(ops) != 2:
                raise E("li needs rd, imm")
            return li_sequence(reg(ops[0], line_no), parse_int(ops[1], line_no))
        if m == "la":
            # Always two words, so pass 1 and pass 2 agree even for a forward
            # label. The pair is lui(upper) + addi(signed low 12).
            if len(ops) != 2:
                raise E("la needs rd, label")
            rd = reg(ops[0], line_no)
            value = self.label_or_int(ops[1], line_no) & 0xFFFFFFFF
            low = value & 0xFFF
            simm12 = low - 0x1000 if low & 0x800 else low
            upper = ((value - simm12) >> 12) & 0xFFFFF
            return [enc_u(0b0110111, rd, upper),
                    enc_i(0b0010011, 0b000, rd, rd, simm12)]
        if m == "mv":
            return [enc_i(0b0010011, 0b000, reg(ops[0], line_no), reg(ops[1], line_no), 0)]
        if m == "not":
            return [enc_i(0b0010011, 0b100, reg(ops[0], line_no), reg(ops[1], line_no), -1)]
        if m == "neg":
            return [enc_r(*R_TYPE["sub"], reg(ops[0], line_no), 0, reg(ops[1], line_no))]
        if m == "seqz":
            return [enc_i(0b0010011, 0b011, reg(ops[0], line_no), reg(ops[1], line_no), 1)]
        if m == "snez":
            return [enc_r(*R_TYPE["sltu"], reg(ops[0], line_no), 0, reg(ops[1], line_no))]
        if m == "sltz":
            return [enc_r(*R_TYPE["slt"], reg(ops[0], line_no), reg(ops[1], line_no), 0)]
        if m == "sgtz":
            return [enc_r(*R_TYPE["slt"], reg(ops[0], line_no), 0, reg(ops[1], line_no))]
        if m == "j":
            return self.encode("jal", ["x0", ops[0]], pc, line_no)
        if m == "call":
            return self.encode("jal", ["x1", ops[0]], pc, line_no)
        if m == "jr":
            return self.encode("jalr", ["x0", f"0({ops[0]})"], pc, line_no)
        if m == "ret":
            return self.encode("jalr", ["x0", "0(x1)"], pc, line_no)
        if m in ("beqz", "bnez", "blez", "bgez", "bltz", "bgtz"):
            real = {"beqz": ("beq", False), "bnez": ("bne", False),
                    "blez": ("bge", True),  "bgez": ("bge", False),
                    "bltz": ("blt", False), "bgtz": ("blt", True)}[m]
            name, swap = real
            a, b = ops[0], "x0"
            if swap:
                a, b = b, a
            return self.encode(name, [a, b, ops[1]], pc, line_no)
        if m in ("bgt", "ble", "bgtu", "bleu"):
            name = {"bgt": "blt", "ble": "bge", "bgtu": "bltu", "bleu": "bgeu"}[m]
            return self.encode(name, [ops[1], ops[0], ops[2]], pc, line_no)

        # ---------------- real instructions ----------------------------------
        if m in R_TYPE:
            if len(ops) != 3:
                raise E(f"{m} needs rd, rs1, rs2")
            op, f3, f7 = R_TYPE[m]
            return [enc_r(op, f3, f7, reg(ops[0], line_no),
                          reg(ops[1], line_no), reg(ops[2], line_no))]

        if m in I_ARITH:
            if len(ops) != 3:
                raise E(f"{m} needs rd, rs1, imm")
            op, f3 = I_ARITH[m]
            imm = self.label_or_int(ops[2], line_no)
            if not fits_signed(imm, 12):
                raise E(f"{m} immediate {imm} does not fit in 12 signed bits")
            return [enc_i(op, f3, reg(ops[0], line_no), reg(ops[1], line_no), imm)]

        if m in I_SHIFT:
            if len(ops) != 3:
                raise E(f"{m} needs rd, rs1, shamt")
            op, f3, f7 = I_SHIFT[m]
            sh = parse_int(ops[2], line_no)
            if not 0 <= sh <= 31:
                raise E(f"{m} shift amount {sh} must be 0..31")
            return [enc_i(op, f3, reg(ops[0], line_no), reg(ops[1], line_no),
                          (f7 << 5) | sh)]

        if m in LOADS:
            if len(ops) != 2:
                raise E(f"{m} needs rd, offset(rs1)")
            off, base = parse_mem(ops[1], line_no)
            imm = self.label_or_int(str(off), line_no)
            if not fits_signed(imm, 12):
                raise E(f"{m} offset {imm} does not fit in 12 signed bits")
            return [enc_i(0b0000011, LOADS[m], reg(ops[0], line_no),
                          reg(base, line_no), imm)]

        if m in STORES:
            if len(ops) != 2:
                raise E(f"{m} needs rs2, offset(rs1)")
            off, base = parse_mem(ops[1], line_no)
            imm = self.label_or_int(str(off), line_no)
            if not fits_signed(imm, 12):
                raise E(f"{m} offset {imm} does not fit in 12 signed bits")
            return [enc_s(0b0100011, STORES[m], reg(base, line_no),
                          reg(ops[0], line_no), imm)]

        if m in BRANCH:
            if len(ops) != 3:
                raise E(f"{m} needs rs1, rs2, label")
            # A label or a bare number both name an absolute address, exactly
            # as GNU as treats them; the encoder stores target - pc.
            target = self.label_or_int(ops[2], line_no)
            offset = target - pc
            if offset % 2:
                raise E(f"{m} target must be even")
            if not fits_signed(offset, 13):
                raise E(f"{m} offset {offset} out of +/-4 KiB range")
            return [enc_b(0b1100011, BRANCH[m], reg(ops[0], line_no),
                          reg(ops[1], line_no), offset)]

        if m == "jal":
            if len(ops) == 1:
                rd, tgt = 1, ops[0]              # `jal label` implies ra
            elif len(ops) == 2:
                rd, tgt = reg(ops[0], line_no), ops[1]
            else:
                raise E("jal needs [rd,] label")
            target = self.label_or_int(tgt, line_no)
            offset = target - pc
            if offset % 2:
                raise E("jal target must be even")
            if not fits_signed(offset, 21):
                raise E(f"jal offset {offset} out of +/-1 MiB range")
            return [enc_j(0b1101111, rd, offset)]

        if m == "jalr":
            if len(ops) == 1:
                return [enc_i(0b1100111, 0b000, 1, reg(ops[0], line_no), 0)]
            if len(ops) == 2:
                off, base = parse_mem(ops[1], line_no)
                return [enc_i(0b1100111, 0b000, reg(ops[0], line_no),
                              reg(base, line_no), self.label_or_int(str(off), line_no))]
            if len(ops) == 3:   # jalr rd, rs1, imm
                return [enc_i(0b1100111, 0b000, reg(ops[0], line_no),
                              reg(ops[1], line_no), parse_int(ops[2], line_no))]
            raise E("jalr form not recognised")

        if m in ("lui", "auipc"):
            if len(ops) != 2:
                raise E(f"{m} needs rd, imm20")
            imm = parse_int(ops[1], line_no)
            if not 0 <= imm <= 0xFFFFF and not fits_signed(imm, 20):
                raise E(f"{m} immediate {imm} out of 20-bit range")
            op = 0b0110111 if m == "lui" else 0b0010111
            return [enc_u(op, reg(ops[0], line_no), imm)]

        raise E(f"unknown instruction '{m}'")

    # ---- output -------------------------------------------------------------
    def assemble(self, src):
        toks = self.tokenise(src)
        self.layout(toks)
        self.emit(toks)
        return self

    def hex_text(self):
        if not self.text:
            return ""
        size = max(a for a, *_ in self.text) // 4 + 1
        img = [0] * size
        for a, w, *_ in self.text:
            img[a // 4] = w
        return "".join(f"{w:08x}\n" for w in img)

    def hex_data(self):
        if not self.data:
            return ""
        size = max(a for a, _ in self.data) // 4 + 1
        img = [0] * size
        for a, w in self.data:
            img[a // 4] = w
        return "".join(f"{w:08x}\n" for w in img)

    def listing(self):
        lines = ["addr      machine   source",
                 "--------  --------  ------------------------------------------"]
        last = None
        for a, w, src, ln in self.text:
            show = src if src != last else ""
            last = src
            lines.append(f"{a:08x}  {w:08x}  {show}")
        if self.data:
            lines += ["", "data section:",
                      "addr      value",
                      "--------  --------"]
            for a, w in self.data:
                lines.append(f"{a:08x}  {w:08x}")
        if self.labels:
            lines += ["", "symbols:"]
            for k, v in sorted(self.labels.items(), key=lambda kv: kv[1]):
                lines.append(f"  {k:<16} 0x{v:08x}")
        return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser(description="Assemble RV32I for the single-cycle core")
    ap.add_argument("source")
    ap.add_argument("-o", "--out", required=True,
                    help="output base name (writes .hex, .data.hex, .lst)")
    args = ap.parse_args()

    with open(args.source) as f:
        src = f.read()

    try:
        asm = Assembler().assemble(src)
    except AsmError as e:
        print(f"asm.py: {e}", file=sys.stderr)
        sys.exit(1)

    with open(args.out + ".hex", "w") as f:
        f.write(asm.hex_text())
    data = asm.hex_data()
    with open(args.out + ".data.hex", "w") as f:
        f.write(data if data else "00000000\n")
    with open(args.out + ".lst", "w") as f:
        f.write(asm.listing())

    n = len(asm.text)
    print(f"asm.py: {args.source} -> {args.out}.hex  "
          f"({n} instructions, {len(asm.data)} data words)")


if __name__ == "__main__":
    main()
