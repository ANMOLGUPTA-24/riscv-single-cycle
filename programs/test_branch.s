# =============================================================================
# test_branch.s - all six conditional branches, taken and not taken
# -----------------------------------------------------------------------------
# Style: each correct outcome bumps the pass counter s0; any wrong outcome falls
# through to `fail`, which sets s1 to a marker the testbench looks for. The
# signed/unsigned pairs use -3 vs 5, which is the case that separates a correct
# comparator from a broken one.
# =============================================================================
    .text
    li    s0, 0               # pass counter
    li    s1, 0               # failure marker
    li    t0, 5
    li    t1, 5
    li    t2, -3
    li    t3, 7

    beq   t0, t1, b1          # taken: 5 == 5
    j     fail
b1: addi  s0, s0, 1           # 1

    bne   t0, t1, fail        # not taken
    addi  s0, s0, 1           # 2

    bne   t0, t3, b2          # taken: 5 != 7
    j     fail
b2: addi  s0, s0, 1           # 3

    blt   t2, t0, b3          # taken: -3 < 5 signed
    j     fail
b3: addi  s0, s0, 1           # 4

    blt   t0, t2, fail        # not taken: 5 < -3 is false
    addi  s0, s0, 1           # 5

    bge   t0, t1, b4          # taken: equal counts as >=
    j     fail
b4: addi  s0, s0, 1           # 6

    bge   t2, t0, fail        # not taken: -3 >= 5 is false
    addi  s0, s0, 1           # 7

    bltu  t0, t2, b5          # taken: 5 < 0xFFFFFFFD unsigned
    j     fail
b5: addi  s0, s0, 1           # 8

    bltu  t2, t0, fail        # not taken unsigned
    addi  s0, s0, 1           # 9

    bgeu  t2, t0, b6          # taken: 0xFFFFFFFD >= 5 unsigned
    j     fail
b6: addi  s0, s0, 1           # 10

    bgeu  t0, t2, fail        # not taken unsigned
    addi  s0, s0, 1           # 11

    # ---- a backward branch driving a loop: sum 1..10 -----------------------
    li    a0, 0               # accumulator
    li    a1, 1               # counter
    li    t4, 11
loop:
    add   a0, a0, a1
    addi  a1, a1, 1
    blt   a1, t4, loop        # a0 = 55 when this finishes
    addi  s0, s0, 1           # 12

    j     halt
fail:
    li    s1, 0xBAD
halt:
    j     halt
