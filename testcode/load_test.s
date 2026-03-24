 .align  4
    .option norvc
    .globl  _start

    .section .data
    .balign 16
buf:
    # 0x00 .. 0x3F (64 bytes) of test data
    .word 0x11112222  # [0]
    .word 0x33334444  # [4]
    .word 0x55556666  # [8]
    .word 0x77778888  # [12]
    .word 0x9999AAAA  # [16]
    .word 0xBBBBCCCC  # [20]
    .word 0xDDDD1111  # [24]
    .word 0x22223333  # [28]
    .word 0x44445555  # [32]
    .word 0x66667777  # [36]
    .word 0x88889999  # [40]
    .word 0xAAAABBBB  # [44]
    .word 0xCCCCDDDD  # [48]
    .word 0xEEEFFFF0  # [52]
    .word 0x12345678  # [56]
    .word 0xDEADBEEF  # [60]

    .section .text
_start:
    # ---- base pointer ----
    lui   x1, %hi(buf)
    addi  x1, x1, %lo(buf)     # x1 = &buf

    ################################################################
    # Loads (W/H/HU/B/BU) from various offsets (all aligned)
    ################################################################
    lw    x2,   0(x1)          # 3
    lw    x3,   4(x1)
    lw    x4,   8(x1)
    lh    x5,  12(x1)
    lhu   x6,  14(x1)
    lb    x7,  16(x1)
    lbu   x8,  17(x1)
    lh    x9,  18(x1)
    lhu   x10, 20(x1)
    lb    x11, 22(x1)
    lbu   x12, 23(x1)
    lw    x13, 24(x1)
    lw    x14, 28(x1)
    lw    x15, 32(x1)

    ################################################################
    # ALU (register)
    ################################################################
    add   x16, x2,  x3         # 17
    sub   x17, x4,  x2
    xor   x18, x5,  x6
    or    x19, x7,  x8
    and   x20, x9,  x10
    sll   x21, x13, x7         # shift amt = x7[4:0]
    srl   x22, x14, x8
    sra   x23, x15, x11
    slt   x24, x6,  x5
    sltu  x25, x10, x9

    ################################################################
    # ALU (immediates)
    ################################################################
    addi  x26, x16, 123        # 27
    xori  x27, x17, 0x555
    ori   x28, x18, 0x0f0
    andi  x29, x19, 0x0ff
    slli  x30, x20, 5
    srli  x31, x21, 3
    srai  x2,  x22, 7
    addi  x3,  x23, -37
    xori  x4,  x24, 0x3c3
    add   x5,  x25, x26

    ################################################################
    # More loads
    ################################################################
    lbu   x6,  33(x1)          # 37
    lb    x7,  34(x1)
    lhu   x8,  36(x1)
    lh    x9,  38(x1)
    lw    x10, 40(x1)
    lw    x11, 44(x1)

    ################################################################
    # More ALU mixing
    ################################################################
    add   x12, x10, x11        # 43
    sub   x13, x12, x14
    xor   x14, x13, x30
    or    x15, x29, x28
    and   x16, x15, x27
    sll   x17, x16, x7
    srl   x18, x17, x6
    sra   x19, x18, x8
    slt   x20, x19, x9
    sltu  x21, x31, x2
    addi  x22, x21, 2047
    andi  x23, x22, 1023
    xori  x24, x23, 0x7f7
    ori   x25, x24, 0x080
    add   x26, x25, x5
    sub   x27, x26, x3
    addi  x28, x27, -512
    add   x29, x28, x4
    slli  x30, x29, 1
    srli  x31, x30, 1          # 62
    
    slti x0, x0, -256