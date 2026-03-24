    .align  4
    .option norvc
    .globl  _start

# Allowed ISA used:
#   LUI, ADDI, ADD, SUB, XOR, OR, AND
#   SLLI, SRLI, SRAI
#   SLT, SLTU, SLTI, SLTIU
#   MUL, MULH, MULHU, MULHSU, DIV, DIVU, REM, REMU
#   LB, LBU, LH, LHU, LW, SB, SH, SW
# No branches or jumps are used.

# ---------------------------------------------------------------------------
# DATA
# ---------------------------------------------------------------------------
    .section .data
    .balign 64
bufA:
    # 0 .. 63
    .word 0x01234567  # 0   lanes [67,45,23,01]
    .word 0x89ABCDEF  # 4   lanes [EF,CD,AB,89]
    .word 0x00000000  # 8
    .word 0xFFFFFFFF  # 12
    .word 0x80000000  # 16  sign-bit patterns
    .word 0x7FFFFFFF  # 20
    .word 0x00008000  # 24
    .word 0x00007FFF  # 28
    .word 0xDEADC0DE  # 32  lanes [DE,C0,AD,DE]
    .word 0x11223344  # 36  lanes [44,33,22,11]
    .word 0x55667788  # 40  lanes [88,77,66,55]
    .word 0x99AABBCC  # 44
    .word 0xF00DBABE  # 48
    .word 0x00000080  # 52
    .word 0x0000007F  # 56
    .word 0x0000FFFF  # 60

    .balign 64
bufB:
    .word 0xA1A2A3A4  # 0
    .word 0xB1B2B3B4  # 4
    .word 0xC1C2C3C4  # 8
    .word 0xD1D2D3D4  # 12

    .balign 64
scratch0:
    .word 0x00000000
scratch1:
    .word 0xFFFFFFFF
scratch2:
    .word 0xCAFED00D
scratch3:
    .word 0xAABBCCDD

# ---------------------------------------------------------------------------
# TEST
# ---------------------------------------------------------------------------
    .section .text
_start:
    # Pointers / accumulators
    lui   x1,  %hi(bufA)             # x1 = &bufA
    addi  x1,  x1, %lo(bufA)
    lui   x20, %hi(scratch0)         # x20 = &scratch0 (mutable word)
    addi  x20, x20, %lo(scratch0)
    lui   x21, %hi(scratch1)         # x21 = &scratch1
    addi  x21, x21, %lo(scratch1)
    lui   x22, %hi(scratch2)         # x22 = &scratch2
    addi  x22, x22, %lo(scratch2)
    lui   x23, %hi(scratch3)         # x23 = &scratch3
    addi  x23, x23, %lo(scratch3)
    lui   x24, %hi(bufB)             # x24 = &bufB
    addi  x24, x24, %lo(bufB)

    addi  x28, x0, 0                 # fail_acc (OR of all mismatches)
    addi  x29, x0, 0                 # checksum spin (keeps pipes busy)
    addi  x26, x0, 0                 # expected
    addi  x27, x0, 0                 # observed
    addi  x30, x0, 0                 # tmp
    addi  x31, x0, 0                 # tmp

# ---- helper inline (no branches) ------------------------------------
# MISMATCH(r, imm):
#   li x26, imm
#   xor x27, r, x26
#   or  x28, x28, x27
# ACCUM(r):
#   xor x29, x29, r
#   slli x30, x29, 1
#   srli x31, x29, 31
#   or  x29, x30, x31

# ---------------------------------------------------------------------
# A. ALU / shifts / (U)SLT(I) sanity (no control)
# ---------------------------------------------------------------------
    li    x2,  0x13579BDF
    li    x3,  0x2468ACE0
    add   x4,  x2,  x3
    li    x26, 0x37C046BF
    xor   x27, x4,  x26
    or    x28, x28, x27

    sub   x5,  x3,  x2
    li    x26, 0x11111101
    xor   x27, x5,  x26
    or    x28, x28, x27

    xor   x6,  x2,  x3
    li    x26, 0x373F372F
    xor   x27, x6,  x26
    or    x28, x28, x27

    or    x7,  x2,  x3
    li    x26, 0x37779BFF
    xor   x27, x7,  x26
    or    x28, x28, x27

    and   x8,  x2,  x3
    li    x26, 0x00480AC0
    xor   x27, x8,  x26
    or    x28, x28, x27

    slli  x9,  x2,  5
    srli  x10, x3,  4
    srai  x11, x3,  4
    # expected for shifts:
    li    x26, 0x6AF37BE0           # x9
    xor   x27, x9, x26
    or    x28, x28, x27
    li    x26, 0x02468ACE           # x10
    xor   x27, x10, x26
    or    x28, x28, x27
    li    x26, 0xF2468ACE           # x11 (arith right)
    xor   x27, x11, x26
    or    x28, x28, x27

    slt   x12, x2,  x3              # 1
    sltu  x13, x3,  x2              # 0
    slti  x14, x2,  -1              # 1
    sltiu x15, x2,  -1              # 1 (since unsigned max)
    li    x26, 1
    xor   x27, x12, x26
    or    x28, x28, x27
    li    x26, 0
    xor   x27, x13, x26
    or    x28, x28, x27
    li    x26, 1
    xor   x27, x14, x26
    or    x28, x28, x27
    li    x26, 1
    xor   x27, x15, x26
    or    x28, x28, x27

    # Mix in some MUL* to tick the M-paths
    li    x16, 0x7FFFFFFF
    li    x17, 0x80000000
    mul   x18, x16, x16             # low
    li    x26, 0x00000001
    sub   x26, x26, x16             # 1 - 0x7fffffff = 0x80000002 (wrong trick) → do expected directly:
    li    x26, 0x00000001
    sub   x26, x26, x0              # keep 1
    addi  x26, x0, -1               # replace with -1 then adjust; easier: compute expected low = 1 (since (2^31-1)^2 = 1 mod 2^32)
    li    x26, 0x00000001
    xor   x27, x18, x26
    or    x28, x28, x27

    mulh  x19, x16, x16             # high half ~ 0x3FFFFFFF
    li    x26, 0x3FFFFFFF
    xor   x27, x19, x26
    or    x28, x28, x27

    mulhsu x5, x17, x16             # neg * pos, signed×unsigned high
    li    x26, 0xC0000000
    xor   x27, x5,  x26
    or    x28, x28, x27

    mulhu x6, x17, x17              # unsigned high of 0x8000_0000^2 = 0x4000_0000
    li    x26, 0x40000000
    xor   x27, x6,  x26
    or    x28, x28, x27

    # DIV/REM edge cases
    li    x2,  0x80000000           # INT_MIN
    addi  x3,  x0, -1               # -1
    div   x4,  x2,  x3              # INT_MIN / -1 = INT_MIN (overflow defined)
    li    x26, 0x80000000
    xor   x27, x4,  x26
    or    x28, x28, x27

    rem   x5,  x2,  x3              # remainder = 0 in that overflow case
    li    x26, 0x00000000
    xor   x27, x5,  x26
    or    x28, x28, x27

    addi  x6,  x0, 0
    div   x7,  x3,  x6              # div by zero (signed) = -1
    li    x26, 0xFFFFFFFF
    xor   x27, x7,  x26
    or    x28, x28, x27
    rem   x8,  x3,  x6              # rem by zero = dividend
    li    x26, 0xFFFFFFFF
    xor   x27, x8,  x26
    or    x28, x28, x27

# ---------------------------------------------------------------------
# B. Loads: sign/zero/lanes on canonical patterns (aligned)
# ---------------------------------------------------------------------
    lw    x2,   0(x1)               # 0x01234567
    xor   x29,  x29, x2             # ACCUM
    slli  x30,  x29, 1
    srli  x31,  x29, 31
    or    x29,  x30, x31
    li    x26, 0x01234567
    xor   x27, x2,  x26
    or    x28, x28, x27

    lbu   x3,   0(x1)               # 0x67
    li    x26, 0x00000067
    xor   x27, x3,  x26
    or    x28, x28, x27

    lb    x4,   3(x1)               # 0x01
    li    x26, 0x00000001
    xor   x27, x4,  x26
    or    x28, x28, x27

    lw    x5,  12(x1)               # 0xFFFFFFFF
    li    x26, 0xFFFFFFFF
    xor   x27, x5,  x26
    or    x28, x28, x27

    lb    x6,  12(x1)               # signed -> 0xFFFFFFFF
    li    x26, 0xFFFFFFFF
    xor   x27, x6,  x26
    or    x28, x28, x27

    lbu   x7,  12(x1)               # 0x000000FF
    li    x26, 0x000000FF
    xor   x27, x7,  x26
    or    x28, x28, x27

    lh    x8,  16(x1)               # 0x8000 -> sign = 0xFFFF8000
    li    x26, 0xFFFF8000
    xor   x27, x8,  x26
    or    x28, x28, x27

    lhu   x9,  16(x1)               # 0x00008000
    li    x26, 0x00008000
    xor   x27, x9,  x26
    or    x28, x28, x27

    lh    x10, 20(x1)               # 0x7FFF -> sign = 0x00007FFF
    li    x26, 0x00007FFF
    xor   x27, x10, x26
    or    x28, x28, x27

    lhu   x11, 20(x1)
    li    x26, 0x00007FFF
    xor   x27, x11, x26
    or    x28, x28, x27

    lh    x12, 34(x1)               # upper half of 0xDEADC0DE @ 32+2 ⇒ 0xDEAD (signed)
    li    x26, 0xFFFFDEAD
    xor   x27, x12, x26
    or    x28, x28, x27

    lhu   x13, 34(x1)               # zero
    li    x26, 0x0000DEAD
    xor   x27, x13, x26
    or    x28, x28, x27

    # lanes from 0x11223344 @ 36
    lbu   x14, 36(x1)               # 0x44
    li    x26, 0x00000044
    xor   x27, x14, x26
    or    x28, x28, x27
    lbu   x15, 37(x1)               # 0x33
    li    x26, 0x00000033
    xor   x27, x15, x26
    or    x28, x28, x27
    lbu   x16, 38(x1)               # 0x22
    li    x26, 0x00000022
    xor   x27, x16, x26
    or    x28, x28, x27
    lbu   x17, 39(x1)               # 0x11
    li    x26, 0x00000011
    xor   x27, x17, x26
    or    x28, x28, x27

# ---------------------------------------------------------------------
# C. Stores + read-back: masks & unaffected lanes
# ---------------------------------------------------------------------
    li    x5,  0xCAFEBABE
    sw    x5,  0(x20)
    lw    x6,  0(x20)
    li    x26, 0xCAFEBABE
    xor   x27, x6, x26
    or    x28, x28, x27

    # halfword overlays
    li    x5,  0x00001234
    sh    x5,  0(x20)               # low half -> 0x1234
    lw    x6,  0(x20)               # expect 0xCAFE1234
    li    x26, 0xCAFE1234
    xor   x27, x6, x26
    or    x28, x28, x27

    lhu   x7,  0(x20)               # 0x1234
    li    x26, 0x00001234
    xor   x27, x7, x26
    or    x28, x28, x27

    lh    x8,  2(x20)               # 0xCAFE -> sign
    li    x26, 0xFFFFCAFE
    xor   x27, x8, x26
    or    x28, x28, x27

    # byte overlays on known word
    li    x5,  0x11223344
    sw    x5,  0(x20)
    li    x5,  0x000000AA
    sb    x5,  1(x20)               # lane1=AA
    li    x5,  0x00000055
    sb    x5,  2(x20)               # lane2=55
    lw    x6,  0(x20)               # 0x1155AA44
    li    x26, 0x1155AA44
    xor   x27, x6, x26
    or    x28, x28, x27

# ---------------------------------------------------------------------
# D. Store→Load forwarding (same address, partial & multi-writer lanes)
# ---------------------------------------------------------------------
    # Single SB then LBU
    li    x5,  0x000000CC
    sb    x5,  0(x20)
    lbu   x6,  0(x20)
    li    x26, 0x000000CC
    xor   x27, x6, x26
    or    x28, x28, x27

    # Two SB + one SH then LW: last-writer wins per lane
    li    x5,  0xAABBCCDD
    sw    x5,  0(x20)
    li    x5,  0x00000011
    sb    x5,  1(x20)               # lane1=11
    li    x5,  0x00000022
    sb    x5,  2(x20)               # lane2=22
    lw    x6,  0(x20)               # expect 0xAA2211DD
    li    x26, 0xAA2211DD
    xor   x27, x6, x26
    or    x28, x28, x27

    # Mixed SH then SB overriding one lane
    li    x5,  0x00007766
    sh    x5,  2(x20)               # lanes2:3 = 0x7766
    li    x5,  0x000000EE
    sb    x5,  1(x20)               # lane1=EE
    lw    x6,  0(x20)               # expect [lane3:0] = [77,66,??,DD] with lane1=EE
    # Recompute expected from current lanes: lane0=DD, lane1=EE, lane2=66, lane3=77
    li    x26, 0x7766EEDD
    xor   x27, x6, x26
    or    x28, x28, x27

# ---------------------------------------------------------------------
# E. No future-forwarding (load old, then store new, then load sees new)
# ---------------------------------------------------------------------
    li    x5,  0xDEADBEEF
    sw    x5,  0(x21)               # write to scratch1
    lw    x6,  0(x21)               # must see old (DEADBEEF)
    li    x26, 0xDEADBEEF
    xor   x27, x6, x26
    or    x28, x28, x27

    li    x5,  0xCAFED00D
    sw    x5,  0(x21)
    lw    x7,  0(x21)               # must see new (CAFED00D)
    li    x26, 0xCAFED00D
    xor   x27, x7, x26
    or    x28, x28, x27

    # Partial-width variant: write high half later, check first load sees old
    li    x5,  0x12345678
    sw    x5,  0(x22)               # scratch2 = 0x12345678
    lhu   x6,  0(x22)               # low half should be 0x5678 now
    li    x26, 0x00005678
    xor   x27, x6, x26
    or    x28, x28, x27

    li    x5,  0x0000ABCD
    sh    x5,  2(x22)               # high half becomes 0xABCD
    lw    x7,  0(x22)               # full should be 0xABCD5678
    li    x26, 0xABCD5678
    xor   x27, x7, x26
    or    x28, x28, x27

# ---------------------------------------------------------------------
# F. Aliasing: distinct bases with same low bits should not mix
# ---------------------------------------------------------------------
    # bufB[0] and scratch3 share low address bits modulo 16? Ensure no false fwd.
    lw    x2,  0(x24)               # bufB[0] = 0xA1A2A3A4
    lw    x3,  0(x23)               # scratch3 = 0xAABBCCDD
    li    x26, 0xA1A2A3A4
    xor   x27, x2, x26
    or    x28, x28, x27
    li    x26, 0xAABBCCDD
    xor   x27, x3, x26
    or    x28, x28, x27

    # Write bufB, ensure scratch3 unaffected
    li    x5,  0x01020304
    sw    x5,  0(x24)
    lw    x6,  0(x24)
    li    x26, 0x01020304
    xor   x27, x6, x26
    or    x28, x28, x27
    lw    x7,  0(x23)
    li    x26, 0xAABBCCDD
    xor   x27, x7, x26
    or    x28, x28, x27

# ---------------------------------------------------------------------
# G. Load-use hazards: use value immediately as data and address
# ---------------------------------------------------------------------
    lw    x2,  40(x1)               # 0x55667788
    addi  x3,  x2, 1
    li    x26, 0x55667789
    xor   x27, x3, x26
    or    x28, x28, x27

    lhu   x4,  40(x1)               # 0x00007788
    addi  x5,  x4, 2
    li    x26, 0x0000778A
    xor   x27, x5, x26
    or    x28, x28, x27

    # Use loaded value to compute an aligned address (mask to keep aligned)
    lw    x6,  36(x1)               # 0x11223344
    andi: addi x31, x0, 0           # dummy label for readability
    and   x7,  x6,  0xFFFFFFFC      # keep word-aligned lower bits
    # Build base = &bufA + 32 (points to 0xDEADC0DE)
    lui   x8,  %hi(bufA)
    addi  x8,  x8, %lo(bufA)
    addi  x8,  x8, 32
    add   x9,  x8,  x7               # still aligned because x7 low two bits cleared
    lw    x10, 0(x8)                 # golden read 0xDEADC0DE
    lw    x11, 0(x9)                 # same word
    li    x26, 0xDEADC0DE
    xor   x27, x10, x26
    or    x28, x28, x27
    xor   x27, x11, x26
    or    x28, x28, x27

# ---------------------------------------------------------------------
# H. Queue pressure: burst stores then loads (8 deep each)
# ---------------------------------------------------------------------
    # Write 8 consecutive words to scratch0 region (use x20 as base)
    li    x5,  0x10000000
    sw    x5,  0(x20)
    addi  x5,  x5, 1
    sw    x5,  4(x20)
    addi  x5,  x5, 1
    sw    x5,  8(x20)
    addi  x5,  x5, 1
    sw    x5,  12(x20)
    addi  x5,  x5, 1
    sw    x5,  16(x20)
    addi  x5,  x5, 1
    sw    x5,  20(x20)
    addi  x5,  x5, 1
    sw    x5,  24(x20)
    addi  x5,  x5, 1
    sw    x5,  28(x20)

    # Read back in reverse order to stress reordering & ready/resp interlock
    lw    x6,  28(x20)
    li    x26, 0x10000007
    xor   x27, x6, x26
    or    x28, x28, x27

    lw    x6,  24(x20)
    li    x26, 0x10000006
    xor   x27, x6, x26
    or    x28, x28, x27

    lw    x6,  20(x20)
    li    x26, 0x10000005
    xor   x27, x6, x26
    or    x28, x28, x27

    lw    x6,  16(x20)
    li    x26, 0x10000004
    xor   x27, x6, x26
    or    x28, x28, x27

    lw    x6,  12(x20)
    li    x26, 0x10000003
    xor   x27, x6, x26
    or    x28, x28, x27

    lw    x6,   8(x20)
    li    x26, 0x10000002
    xor   x27, x6, x26
    or    x28, x28, x27

    lw    x6,   4(x20)
    li    x26, 0x10000001
    xor   x27, x6, x26
    or    x28, x28, x27

    lw    x6,   0(x20)
    li    x26, 0x10000000
    xor   x27, x6, x26
    or    x28, x28, x27

# ---------------------------------------------------------------------
# I. Store→Load forwarding with mixed lanes & partial miss merge
# ---------------------------------------------------------------------
    # Craft word with 2 lanes from SB and 2 lanes from memory
    li    x5,  0x44332211
    sw    x5,  0(x23)               # scratch3 = 0x44332211
    li    x5,  0x000000AA
    sb    x5,  0(x23)               # lane0 = AA
    li    x5,  0x000000BB
    sb    x5,  2(x23)               # lane2 = BB
    # Now LW should merge lanes: [lane3..0] = [44,BB,22,AA] => 0x44BB22AA
    lw    x6,  0(x23)
    li    x26, 0x44BB22AA
    xor   x27, x6,  x26
    or    x28, x28, x27

    # Read LHU at offset 2 to check half assembled from SB + memory lane
    lhu   x7,  2(x23)               # lanes [lane3:2] -> [44,BB] => 0x44BB
    li    x26, 0x000044BB
    xor   x27, x7,  x26
    or    x28, x28, x27

# ---------------------------------------------------------------------
# J. Finish (pass/fail marker) — same convention as your earlier tests
# ---------------------------------------------------------------------
    sltu  x30, x0, x28              # x30 = 1 if any mismatch
    li    x1,  0xAAAAB000
    add   x1,  x1, x30
    slti  x0,  x0, -256             # "halt"
