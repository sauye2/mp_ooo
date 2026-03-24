div_smoke.s:
    .align 4
    .section .text
    .globl _start
_start:
    # --------- Constants (minimal) ---------
    addi x1,  x0, 1
    addi x2,  x0, 2
    addi x3,  x0, -1                 # 0xFFFFFFFF (-1)
    lui  x4,  0x80000                # 0x80000000 (INT_MIN)
    lui  x5,  0x7FFFF
    addi x5,  x5, 0x7FF              # 0x7FFFFFFF (INT_MAX)
    addi x6,  x0, 0
    addi x7,  x0, 42
    addi x8,  x0, -42
    addi x9,  x0, 7

    # --------- DIV (signed) ---------
    div  x10, x7,  x9                # 42 / 7  = 6
    div  x11, x8,  x9                # -42 / 7 = -6
    div  x12, x7,  x8                # 42 / -42 = -1
    div  x13, x8,  x8                # -42 / -42 = 1
    div  x14, x7,  x6                # /0 -> -1
    div  x15, x4,  x3                # INT_MIN / -1 -> INT_MIN (per spec)

    # --------- DIVU (unsigned) ---------
    divu x16, x4,  x2                # 0x80000000 / 2u -> 0x40000000
    divu x17, x6,  x2                # 0 / 2u = 0
    divu x18, x3,  x2                # 0xFFFFFFFF / 2u -> 0x7FFFFFFF
    divu x19, x5,  x6                # /0 -> 0xFFFFFFFF

    # --------- REM (signed) ---------
    rem  x20, x7,  x9                # 42 % 7 = 0
    rem  x21, x8,  x9                # -42 % 7 = 0 (remainder sign follows dividend)
    rem  x22, x5,  x2                # INT_MAX % 2 = 1
    rem  x23, x4,  x3                # INT_MIN % -1 = 0
    rem  x24, x7,  x6                # %0 -> remainder = dividend (42)

    # --------- REMU (unsigned) ---------
    remu x25, x9,  x7                # 7u % 42u = 7
    remu x26, x3,  x2                # 0xFFFFFFFF % 2u = 1
    remu x27, x5,  x6                # %0 -> remainder = dividend (INT_MAX)
    remu x28, x6,  x9                # 0u % 7u = 0

halt:
    slti x0, x0, -256                # harmless "halt" (writes to x0)