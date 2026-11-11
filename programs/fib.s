# =============================================================================
# fib.s - write the first 15 Fibonacci numbers to data memory
# -----------------------------------------------------------------------------
# The classic demo program: a loop, an accumulator, an array walk and a store
# per iteration. Result in data memory words 0..14:
#   0 1 1 2 3 5 8 13 21 34 55 89 144 233 377
# =============================================================================
    .text
    li    t0, 0               # write pointer (byte address)
    li    t1, 0               # fib(i-2)
    li    t2, 1               # fib(i-1)
    li    t3, 15              # how many to produce
    li    t4, 0               # i

loop:
    sw    t1, 0(t0)           # store fib(i)
    add   t5, t1, t2          # fib(i+1) = fib(i-1) + fib(i)
    mv    t1, t2
    mv    t2, t5
    addi  t0, t0, 4
    addi  t4, t4, 1
    blt   t4, t3, loop

    lw    a0, 56(x0)          # a0 = word 14 = fib(14) = 377
    li    a1, 15              # a1 = number of values written

halt:
    j     halt
