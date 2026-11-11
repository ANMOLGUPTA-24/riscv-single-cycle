# =============================================================================
# gcd.s - greatest common divisor by repeated subtraction (Euclid)
# -----------------------------------------------------------------------------
# gcd(1071, 462) = 21. Short, but it leans on exactly the parts that are easy
# to get wrong: a loop with two exit paths and a signed comparison.
# =============================================================================
    .text
    li    a0, 1071
    li    a1, 462

loop:
    beq   a0, a1, done
    blt   a0, a1, a_smaller
    sub   a0, a0, a1          # a > b : a = a - b
    j     loop
a_smaller:
    sub   a1, a1, a0          # b > a : b = b - a
    j     loop

done:
    mv    a2, a0              # a2 = gcd = 21
    sw    a2, 0(x0)           # and leave it in data memory word 0
halt:
    j     halt
