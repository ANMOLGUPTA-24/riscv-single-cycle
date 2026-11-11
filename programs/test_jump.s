# =============================================================================
# test_jump.s - jal, jalr, ret, lui, auipc
# -----------------------------------------------------------------------------
# The interesting check here is auipc: the program proves it by comparing
# `auipc t1, 0` (which must give the address of that very instruction) against
# the link address that `jal t2, nxt` writes. If the PC that feeds the ALU and
# the PC that feeds the write-back path ever disagree, this test catches it.
# =============================================================================
    .text
    li    s0, 0               # pass counter
    li    s1, 0               # failure marker
    li    s6, 0               # accumulator touched only by subroutines

    jal   ra, func            # call: s6 += 100, then ret
    addi  s0, s0, 1           # 1: we came back to the right place

    j     skip                # jal x0: unconditional jump, no link
    li    s1, 0xBAD           # must never execute
skip:
    addi  s0, s0, 1           # 2

    la    t0, target          # absolute address of a subroutine
    jalr  ra, 0(t0)           # indirect call: s6 += 10, then ret
    addi  s0, s0, 1           # 3

cur:
    auipc t1, 0               # t1 = address of `cur`
    jal   t2, nxt             # t2 = address of this jal + 4 = cur + 8
nxt:
    addi  t3, t1, 8
    bne   t3, t2, fail        # auipc and the link address must agree
    addi  s0, s0, 1           # 4

    lui   t4, 0x12345         # 0x12345000
    li    t5, 0x12345000
    bne   t4, t5, fail
    addi  s0, s0, 1           # 5

    j     halt

func:
    addi  s6, s6, 100
    ret                       # jalr x0, 0(ra)

target:
    addi  s6, s6, 10
    ret

fail:
    li    s1, 0xBAD
halt:
    j     halt
