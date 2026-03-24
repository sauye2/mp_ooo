    .align  4
    .option norvc
    .globl  _start

# Uses only: LUI, ADDI, ADD/SUB/XOR/OR/AND, shifts, SLT/SLTU/SLTI/SLTIU,
# and loads/stores (LB/LBU/LH/LHU/LW, SB/SH/SW). No branches or jumps.

    .section .data
    .balign 64
buf:
    .word 0x01234567  # [0]   lanes [67,45,23,01]
    .word 0x89ABCDEF  # [4]   lanes [EF,CD,AB,89]
    .word 0x00000000  # [8]
    .word 0xFFFFFFFF  # [12]
    .word 0x00008000  # [16]
    .word 0x00007FFF  # [20]
    .word 0x80000000  # [24]
    .word 0x7FFFFFFF  # [28]
    .word 0xF00DBABE  # [32]
    .word 0xDEADC0DE  # [36]  lanes [DE,C0,AD,DE]
    .word 0x11223344  # [40]  lanes [44,33,22,11]
    .word 0x55667788  # [44]  lanes [88,77,66,55]
    .word 0x99AABBCC  # [48]
    .word 0xDDEEFF00  # [52]
    .word 0x00000080  # [56]
    .word 0x0000007F  # [60]

    .balign 16
scratch:
    .word 0xAABBCCDD

    .section .text
_start:
    # -------------------------------------------------------------------------
    # Setup pointers and flags
    # -------------------------------------------------------------------------
    lui   x1,  %hi(buf)
    addi  x1,  x1, %lo(buf)         # x1 = &buf
    lui   x20, %hi(scratch)
    addi  x20, x20, %lo(scratch)    # x20 = &scratch

    addi  x28, x0, 0                # fail_acc (OR of all mismatches)
    addi  x29, x0, 0                # checksum accumulator (keeps LSU busy)
    addi  x26, x0, 0                # expected
    addi  x27, x0, 0                # observed
    addi  x30, x0, 0                # temp
    addi  x31, x0, 0                # temp

    # A tiny helper pattern without control:
    #   MISMATCH(r, imm):
    #       li x26, imm
    #       xor x27, r, x26
    #       or  x28, x28, x27
    #
    #   ACCUM(r):
    #       xor x29, x29, r
    #       slli x30, x29, 1
    #       srli x31, x29, 31
    #       or  x29, x30, x31

    # -------------------------------------------------------------------------
    # Section A: Loads (sign/zero rules), aligned
    # -------------------------------------------------------------------------
    lw    x2,   0(x1)               # 0x01234567
    xor   x29,  x29, x2             # ACCUM x2
    slli  x30,  x29, 1
    srli  x31,  x29, 31
    or    x29,  x30, x31
    li    x26,  0x01234567
    xor   x27,  x2,  x26
    or    x28,  x28, x27

    lbu   x3,   0(x1)               # 0x67
    li    x26,  0x00000067
    xor   x27,  x3,  x26
    or    x28,  x28, x27

    lb    x4,   3(x1)               # 0x01
    li    x26,  0x00000001
    xor   x27,  x4,  x26
    or    x28,  x28, x27

    lw    x5,  12(x1)               # 0xFFFFFFFF
    li    x26, 0xFFFFFFFF
    xor   x27, x5,  x26
    or    x28, x28, x27

    lb    x6,  12(x1)               # 0xFFFFFFFF (sign)
    li    x26, 0xFFFFFFFF
    xor   x27, x6,  x26
    or    x28, x28, x27

    lbu   x7,  12(x1)               # 0x000000FF
    li    x26, 0x000000FF
    xor   x27, x7,  x26
    or    x28, x28, x27

    lh    x8,  16(x1)               # 0xFFFF8000
    li    x26, 0xFFFF8000
    xor   x27, x8,  x26
    or    x28, x28, x27

    lhu   x9,  16(x1)               # 0x00008000
    li    x26, 0x00008000
    xor   x27, x9,  x26
    or    x28, x28, x27

    lh    x10, 20(x1)               # 0x00007FFF
    li    x26, 0x00007FFF
    xor   x27, x10, x26
    or    x28, x28, x27

    lhu   x11, 20(x1)               # 0x00007FFF
    li    x26, 0x00007FFF
    xor   x27, x11, x26
    or    x28, x28, x27

    # Upper half of 0xDEADC0DE at [36] with off=2 → 0xDEAD
    lh    x12, 38(x1)               # sign
    li    x26, 0xFFFFDEAD
    xor   x27, x12, x26
    or    x28, x28, x27

    lhu   x13, 38(x1)               # zero
    li    x26, 0x0000DEAD
    xor   x27, x13, x26
    or    x28, x28, x27

    # Lanes from 0x11223344 @ [40]
    lbu   x14, 40(x1)               # 0x44
    li    x26, 0x00000044
    xor   x27, x14, x26
    or    x28, x28, x27

    lbu   x15, 41(x1)               # 0x33
    li    x26, 0x00000033
    xor   x27, x15, x26
    or    x28, x28, x27

    lbu   x16, 42(x1)               # 0x22
    li    x26, 0x00000022
    xor   x27, x16, x26
    or    x28, x28, x27

    lbu   x17, 43(x1)               # 0x11
    li    x26, 0x00000011
    xor   x27, x17, x26
    or    x28, x28, x27

    # -------------------------------------------------------------------------
    # Section B: Stores and read-back (width masking and lane placement)
    # -------------------------------------------------------------------------
    li    x21, 0xCAFEBABE
    sw    x21, 0(x20)
    lw    x22, 0(x20)
    li    x26, 0xCAFEBABE
    xor   x27, x22, x26
    or    x28, x28, x27

    lh    x23, 0(x20)               # low half sign of 0xBABE
    li    x26, 0xFFFFBABE
    xor   x27, x23, x26
    or    x28, x28, x27

    lhu   x24, 2(x20)               # upper half 0xCAFE
    li    x26, 0x0000CAFE
    xor   x27, x24, x26
    or    x28, x28, x27

    lbu   x25, 1(x20)               # lane 1 = 0xBE
    li    x26, 0x000000BE
    xor   x27, x25, x26
    or    x28, x28, x27

    # SH then mixed reads
    li    x21, 0x00001234
    sh    x21, 0(x20)               # low half -> 0x1234; top half stays 0xCAFE
    lw    x22, 0(x20)
    li    x26, 0xCAFE1234
    xor   x27, x22, x26
    or    x28, x28, x27

    lhu   x23, 0(x20)
    li    x26, 0x00001234
    xor   x27, x23, x26
    or    x28, x28, x27

    lh    x24, 2(x20)
    li    x26, 0xFFFFCAFE
    xor   x27, x24, x26
    or    x28, x28, x27

    # SB overlaps on known word 0x11223344
    li    x21, 0x11223344
    sw    x21, 0(x20)
    li    x21, 0x000000AA
    sb    x21, 1(x20)
    li    x21, 0x00000055
    sb    x21, 2(x20)
    lw    x22, 0(x20)               # expected 0x1155AA44
    li    x26, 0x1155AA44
    xor   x27, x22, x26
    or    x28, x28, x27

    # -------------------------------------------------------------------------
    # Section C: Store→Load forwarding (same address), partial overlaps
    # -------------------------------------------------------------------------
    li    x21, 0x000000CC
    sb    x21, 0(x20)
    lbu   x22, 0(x20)
    li    x26, 0x000000CC
    xor   x27, x22, x26
    or    x28, x28, x27

    li    x21, 0x000000EE
    sb    x21, 1(x20)               # lane 1 = 0xEE
    li    x21, 0x00007766
    sh    x21, 2(x20)               # lanes 2:3 = 0x7766
    lhu   x22, 2(x20)
    li    x26, 0x00007766
    xor   x27, x22, x26
    or    x28, x28, x27

    # Two SB then LW combine
    li    x21, 0xAABBCCDD
    sw    x21, 0(x20)
    li    x21, 0x00000011
    sb    x21, 1(x20)
    li    x21, 0x00000022
    sb    x21, 2(x20)
    lw    x22, 0(x20)
    li    x26, 0xAA2211DD
    xor   x27, x22, x26
    or    x28, x28, x27

    # -------------------------------------------------------------------------
    # Section D: Ordering (no future-forwarding)
    #   First load old, then store new, then load new.
    # -------------------------------------------------------------------------
    li    x21, 0xDEADBEEF
    sw    x21, 0(x20)
    lw    x22, 0(x20)               # should see old
    li    x26, 0xDEADBEEF
    xor   x27, x22, x26
    or    x28, x28, x27

    li    x21, 0xCAFED00D
    sw    x21, 0(x20)
    lw    x23, 0(x20)               # should see new
    li    x26, 0xCAFED00D
    xor   x27, x23, x26
    or    x28, x28, x27

    # -------------------------------------------------------------------------
    # Section E: Load-use hazards (use value in next op)
    # -------------------------------------------------------------------------
    lw    x2,  44(x1)               # 0x55667788
    addi  x3,  x2, 1
    li    x26, 0x55667789
    xor   x27, x3, x26
    or    x28, x28, x27

    lhu   x4,  44(x1)               # 0x00007788
    addi  x5,  x4, 2
    li    x26, 0x0000778A
    xor   x27, x5, x26
    or    x28, x28, x27

    lbu   x6,  45(x1)               # 0x77
    slli  x7,  x6, 1
    li    x26, 0x000000EE
    xor   x27, x7, x26
    or    x28, x28, x27

    # -------------------------------------------------------------------------
    # Section F: Address calc with negative and large offsets
    # -------------------------------------------------------------------------
    addi  x30, x1, 8                # &buf[8]
    addi  x31, x30, -8               # back to &buf[0]
    lw    x2,  0(x31)
    li    x26, 0x01234567
    xor   x27, x2,  x26
    or    x28, x28, x27

    addi  x31, x30, 32               # &buf[40]
    lw    x2,  0(x31)
    li    x26, 0x11223344
    xor   x27, x2,  x26
    or    x28, x28, x27

    # -------------------------------------------------------------------------
    # Section G: A few more mixed-width overlaps on buf itself
    #   Work on a temp copy at scratch, not to disturb earlier checks.
    # -------------------------------------------------------------------------
    lw    x21, 40(x1)                # 0x11223344
    sw    x21, 0(x20)

    li    x21, 0x000000AA
    sb    x21, 0(x20)                # lane 0 -> AA
    li    x21, 0x00000055
    sb    x21, 3(x20)                # lane 3 -> 55
    lw    x22, 0(x20)                # lanes [AA,33,22,55] little-endian → 0x552233AA
    li    x26, 0x552233AA
    xor   x27, x22, x26
    or    x28, x28, x27

    li    x21, 0x00001234
    sh    x21, 0(x20)                # low half = 0x1234
    sh    x21, 2(x20)                # high half = 0x1234
    lw    x22, 0(x20)                # 0x12341234
    li    x26, 0x12341234
    xor   x27, x22, x26
    or    x28, x28, x27

    # -------------------------------------------------------------------------
    # Finish: emit pass/fail marker in x1, then halt
    #   pass => x1 = 0xAAAAB000
    #   fail => x1 = 0xAAAAB001
    # -------------------------------------------------------------------------
    sltu  x30, x0, x28               # x30 = 1 if any mismatch, else 0
    li    x1,  0xAAAAB000
    add   x1,  x1, x30
    slti  x0,  x0, -256
