# =============================================================================
# bubble_sort.s - sort 8 words in data memory, ascending
# -----------------------------------------------------------------------------
# Uses a .data section, so the testbench loads the unsorted array into the data
# memory image before the first clock. This is the program to demo in a viva:
# it needs loads, stores, a nested loop, a signed compare and address
# arithmetic, so a single broken instruction shows up as a wrong result.
#
# Input : 42 7 19 3 88 1 56 23
# Output:  1 3  7 19 23 42 56 88
# =============================================================================
    .data
arr:
    .word 42, 7, 19, 3, 88, 1, 56, 23

    .text
    li    s0, 0               # base address of the array
    li    s1, 8               # n
    addi  s2, s1, -1          # i = n-1

outer:
    blez  s2, done            # finished when i reaches 0
    li    s3, 0               # j = 0

inner:
    bge   s3, s2, next_i      # inner loop runs j = 0 .. i-1
    slli  t0, s3, 2           # j * 4
    add   t0, t0, s0          # &arr[j]
    lw    t1, 0(t0)           # arr[j]
    lw    t2, 4(t0)           # arr[j+1]
    ble   t1, t2, no_swap     # already in order
    sw    t2, 0(t0)           # swap
    sw    t1, 4(t0)
no_swap:
    addi  s3, s3, 1
    j     inner

next_i:
    addi  s2, s2, -1
    j     outer

done:
    lw    a0, 0(s0)           # a0 = smallest element  = 1
    lw    a1, 28(s0)          # a1 = largest element   = 88
halt:
    j     halt
