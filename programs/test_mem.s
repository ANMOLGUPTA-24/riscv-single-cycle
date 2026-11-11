# =============================================================================
# test_mem.s - every load and store width, at every alignment
# -----------------------------------------------------------------------------
# Byte and half-word accesses are where a careless load/store unit goes wrong
# silently: lw keeps working while lb returns the wrong lane. So each lane is
# read back explicitly, in both the sign-extended and zero-extended form.
# =============================================================================
    .text
    li    t0, 0               # base address

    # ---- word round trip ----------------------------------------------------
    li    t1, 0x12345678
    sw    t1, 0(t0)
    lw    t2, 0(t0)           # x7  = 0x12345678

    # ---- byte lanes out of that word ----------------------------------------
    lb    s0, 0(t0)           # x8  = 0x78 -> 0x00000078 (positive)
    lb    s1, 3(t0)           # x9  = 0x12 -> 0x00000012
    lbu   s2, 1(t0)           # x18 = 0x56 -> 0x00000056
    lh    s3, 0(t0)           # x19 = 0x5678 -> 0x00005678
    lh    s4, 2(t0)           # x20 = 0x1234 -> 0x00001234
    lhu   s5, 0(t0)           # x21 = 0x00005678

    # ---- byte stores must not disturb the neighbouring lanes ----------------
    sw    x0, 4(t0)           # clear word 1
    li    t3, 0xFF
    sb    t3, 4(t0)           # lane 0
    sb    t3, 6(t0)           # lane 2
    lw    s6, 4(t0)           # x22 = 0x00FF00FF
    lb    s7, 4(t0)           # x23 = 0xFF sign-extended = 0xFFFFFFFF
    lbu   s8, 4(t0)           # x24 = 0x000000FF

    # ---- half-word stores ----------------------------------------------------
    sw    x0, 8(t0)
    li    t4, 0xABCD
    sh    t4, 8(t0)           # low half
    sh    t4, 10(t0)          # high half
    lw    s9,  8(t0)          # x25 = 0xABCDABCD
    lh    s10, 8(t0)          # x26 = 0xABCD sign-extended = 0xFFFFABCD
    lhu   s11, 8(t0)          # x27 = 0x0000ABCD

    # ---- negative and large offsets -----------------------------------------
    li    a0, 64
    li    a1, 0xDEADBEEF
    sw    a1, -4(a0)          # writes address 60
    lw    a2, 60(x0)          # x12 = 0xDEADBEEF

    # ---- a load does not write x0 -------------------------------------------
    lw    x0, 0(t0)           # x0 stays 0

halt:
    j     halt
