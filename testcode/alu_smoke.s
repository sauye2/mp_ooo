alu_smoke.s:
    .align 4
    .section .text
    .globl _start
_start:
    # --------- Constants (no memory, no branches) ---------
    addi x1,  x0, 1
    addi x2,  x0, 2
    addi x3,  x0, -1                 # 0xFFFFFFFF
    lui  x4,  0x80000                # 0x80000000 (INT_MIN)
    addi x5,  x0, 31
    addi x6,  x0, 0
    addi x7,  x0, 123
    addi x8,  x0, -123
    lui  x9,  0x00010                # 0x00010000
    addi x10, x0, 7
    addi x11, x0, 13
    addi x12, x0, 42
    addi x13, x0, -42
    addi x14, x0, 0
    addi x15, x0, 5
    addi x16, x0, 9
    addi x17, x0, 16
    lui  x18, 0x7FFFF                # 0x7FFFF000
    addi x18, x18, 0x7FF             # 0x7FFFFFFF (INT_MAX)

    # --------- Register-register ALU ---------
    add  x19, x7,  x10               # 123 + 7  = 130
    sub  x20, x12, x11               # 42  - 13 = 29
    xor  x21, x7,  x2                # 123 ^ 2
    or   x22, x7,  x2                # 123 | 2
    and  x23, x7,  x2                # 123 & 2
    slt  x24, x8,  x7                # (-123 < 123) = 1
    sltu x25, x3,  x7                # (0xFFFFFFFF < 123) unsigned = 0
    sll  x26, x9,  x1                # 0x00010000 << 1 = 0x00020000
    srl  x27, x9,  x1                # 0x00010000 >> 1 = 0x00008000 (logical)
    sra  x28, x8,  x1                # -123 >> 1 (arith)

    # --------- Immediate ALU ---------
    addi x29, x7,   10               # 133
    xori x30, x7,   -1               # ~123
    ori  x31, x6,   0xFF             # 0x000000FF (THIS IS AN ISSUE)
    andi x5,  x18,  0xFF             # INT_MAX & 0xFF = 0xFF
    slli x6,  x2,   5                # 2 << 5 = 64
    srli x14, x9,   12               # 0x00010000 >> 12 = 0x10
    srai x15, x8,   3                # -123 >> 3 arith
    slti x16, x12,  100              # 42<100 -> 1
    sltiu x17, x3,  1                # 0xFFFFFFFF < 1 (u)? 0

    # --------- More mixes (still short deps only) ---------
    add  x19, x19,  x1               # 130 + 1 = 131
    sub  x20, x20,  x2               # 29 - 2 = 27
    xor  x21, x21,  x3               # (123^2) ^ -1 = bitwise not
    or   x22, x22,  x3               # anything | -1 = -1
    and  x23, x23,  x18              # keep low bits
    sll  x26, x26,  x1               # shift again by 1
    srl  x27, x27,  x1               # shift again by 1
    sra  x28, x28,  x1               # shift again by 1
    addi x29, x29,  -33              # 133-33 = 100
    andi x31, x31,  0x0F             # 0xF THIS IS ALSO A PROBLEM 

    # --------- LUI sanity beyond INT edges ---------
    lui  x5,  0x12345                # 0x12345000
    addi x5,  x5,   0x678            # 0x12345678
    lui  x6,  0xFFFFF                # 0xFFFFF000 (negative)
    addi x6,  x6,   -1               # 0xFFFFEFFF

    # --------- DIV (signed) edge cases & normals ---------
    # Normal positive / positive
    div  x7,  x12, x10               # 42 / 7 = 6
    # Negative / positive
    div  x8,  x13, x10               # -42 / 7 = -6
    # Positive / negative
    div  x9,  x12, x13               # 42 / -42 = -1
    # Negative / negative
    div  x10, x13, x13               # -42 / -42 = 1
    # Division by zero: quotient = -1
    div  x11, x12, x0                # 42 / 0 -> -1
    # INT_MIN / -1: defined overflow case -> INT_MIN
    div  x12, x4,  x3                # 0x80000000 / -1 -> 0x80000000
    # INT_MAX / 1 -> INT_MAX
    div  x13, x18, x1
    # Mixed smalls
    div  x14, x10, x2                # 1 / 2 = 0 (toward zero)
    div  x15, x7,  x2                # 6 / 2 = 3
    div  x16, x29, x11               # 100 / -1 = -100

    # --------- Final ALU sprinkles ---------
    sltu x17, x18, x4                # (INT_MAX < INT_MIN) unsigned? 0
    slt  x19, x18, x4                # signed: INT_MAX < INT_MIN? 0
    xor  x20, x5,  x6
    and  x21, x5,  x6
    or   x22, x5,  x6
    slli x23, x1,  31                # 1 << 31 = 0x80000000
    srli x24, x23, 31                # back to 1
    srai x25, x4,  31                # INT_MIN >> 31 arith = 0xFFFFFFFF
    add  x26, x18, x3                # INT_MAX + (-1) = INT_MAX-1
    sub  x27, x1,  x2                # 1-2 = -1
    xori x28, x27, -1                # ~(-1) = 0
    andi x29, x28, 0xFF              # 0 & 0xFF = 0
    ori  x30, x29, 0xAA              # 0xAA
    add  x31, x30, x24               # 0xAA + 1 = 0xAB

    


halt:
    slti x0, x0, -256                # harmless "halt" (writes to x0)