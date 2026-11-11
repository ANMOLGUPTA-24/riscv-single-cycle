# =============================================================================
# test_alu.s - exercise every arithmetic / logic instruction
# -----------------------------------------------------------------------------
# Each instruction leaves its result in a register that nothing else touches, so
# the testbench can check all of them at the end. Expected values are in the
# comments and are duplicated in tb_riscv_top.v.
# =============================================================================
    .text
    li    t0, 10              # x5  = 10
    li    t1, 3               # x6  = 3
    li    t2, -16             # x7  = -16 (0xFFFFFFF0)

    # ---- R-type -------------------------------------------------------------
    add   s0,  t0, t1         # x8  = 13
    sub   s1,  t0, t1         # x9  = 7
    and   s2,  t0, t1         # x18 = 1010 & 0011 = 2
    or    s3,  t0, t1         # x19 = 1010 | 0011 = 11
    xor   s4,  t0, t1         # x20 = 1010 ^ 0011 = 9
    sll   s5,  t0, t1         # x21 = 10 << 3 = 80
    srl   s6,  t0, t1         # x22 = 10 >> 3 = 1
    slt   s7,  t1, t0         # x23 = (3 < 10) signed = 1
    sltu  s8,  t0, t1         # x24 = (10 < 3) unsigned = 0
    sra   s9,  t2, t1         # x25 = -16 >> 3 arithmetic = -2 (0xFFFFFFFE)
    srl   s10, t2, t1         # x26 = 0xFFFFFFF0 >> 3 logical = 0x1FFFFFFE
    slt   s11, t2, t1         # x27 = (-16 < 3) signed = 1

    # ---- I-type -------------------------------------------------------------
    sltu  a0,  t2, t1         # x10 = (0xFFFFFFF0 < 3) unsigned = 0
    addi  a1,  t0, -20        # x11 = -10 (0xFFFFFFF6)
    xori  a2,  t0, -1         # x12 = ~10 = 0xFFFFFFF5
    ori   a3,  t0, 5          # x13 = 15
    andi  a4,  t0, 6          # x14 = 2
    slti  a5,  t0, 11         # x15 = 1
    sltiu a6,  t2, 11         # x16 = (0xFFFFFFF0 < 11) unsigned = 0
    slli  a7,  t0, 4          # x17 = 160
    srai  t3,  t2, 2          # x28 = -16 >> 2 arithmetic = -4 (0xFFFFFFFC)
    srli  t4,  t2, 28         # x29 = 0xFFFFFFF0 >> 28 = 0xF
    slli  t5,  t1, 31         # x30 = 3 << 31 = 0x80000000 (bit 1 shifts out)
    sub   t6,  x0, t0         # x31 = -10 (0xFFFFFFF6)

    # ---- x0 must be immune to writes ----------------------------------------
    addi  x0, x0, 99          # x0 stays 0
    add   x0, t0, t1          # x0 stays 0

halt:
    j     halt                # park here; the testbench detects the self-loop
