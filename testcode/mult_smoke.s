mult_smoke.s:
    .align 4
    .section .text
    .globl _start
_start:
    addi x1,  x0, 1
    addi x2,  x0, 2
    addi x3,  x0, -1                 # 0xFFFFFFFF (-1)
    lui  x4,  0x80000                # 0x80000000 (INT_MIN)
    lui  x5,  0x7FFFF                # 0x7FFFF000
    addi x5,  x5, 0x7FF              # 0x7FFFFFFF (INT_MAX)
    addi x6,  x0, 0
    addi x7,  x0, 3
    addi x8,  x0, 5
    addi x9,  x0, 7
    lui  x10, 0x00010                # 0x00010000
    addi x11, x0, 42
    addi x12, x0, -42
    addi x13, x0, 123
    addi x14, x0, -123
    addi x15, x0, 9
    addi x16, x0, 16
# Basics / sanity
    mul  x17, x7,  x8                 # 3*5 = 15
    mul  x18, x6,  x13                # 0*123 = 0
    mul  x19, x3,  x1                 # -1*1 = 0xFFFFFFFF
    mul  x20, x11, x9                 # 42*7 = 294
    mul  x21, x12, x9                 # -42*7 = -294

    # Edges around INT_MIN/INT_MAX
    mul  x22, x4,  x2                 # INT_MIN*2 -> low = 0x00000000
    mul  x23, x5,  x2                 # INT_MAX*2 -> 0xFFFFFFFE (wrap)
    mul  x24, x5,  x1                 # INT_MAX*1 -> INT_MAX
    mul  x25, x14, x2                 # -123*2 = -246
    mul  x26, x13, x15                # 123*9 = 1107 (carry-free small)

    # Small dependency chain (bypass/forwarding)
    addi x27, x0, 7
    mul  x27, x27, x3                 # 7 * (-1) = -7
    mul  x28, x27, x8                 # (-7) * 5 = -35
    mul  x29, x28, x2                 # (-35) * 2 = -70

    # ======================================================
    # =========  MULH (signed×signed, high 32)  ============
    # ======================================================

    mulh x17, x11, x9                 # 42*7 = 294 -> high = 0x00000000
    mulh x18, x12, x9                 # -42*7 = -294 -> high = 0xFFFFFFFF
    mulh x19, x3,  x1                 # (-1)*1 -> product=-1 => high=0xFFFFFFFF
    mulh x20, x4,  x2                 # INT_MIN*2 => 0xFFFFFFFF00000000 -> high=0xFFFFFFFF
    mulh x21, x5,  x2                 # INT_MAX*2 => high = 0x00000000
    mulh x22, x4,  x4                 # (−2^31)^2=2^62 -> high=0x40000000
    mulh x23, x13, x14                # 123 * (-123) -> negative => high=0xFFFFFFFF

    # ======================================================
    # =======  MULHU (unsigned×unsigned, high 32)  =========
    # ======================================================

    mulhu x24, x11, x9                # 42u*7u=294 -> high=0
    mulhu x25, x10, x10               # 0x10000*0x10000 = 0x00000001_00000000 -> high=1
    mulhu x26, x4,  x2                # 0x80000000*2 = 0x00000001_00000000 -> high=1
    mulhu x27, x5,  x5                # (0x7fffffff^2) -> high ~= 0x3fffffff
    mulhu x28, x3,  x3                # 0xffffffff*0xffffffff -> high=0xfffffffe
    mulhu x29, x4,  x3                # 0x80000000*0xffffffff -> high=0x7fffffff

    # ======================================================
    # ======  MULHSU (signed×unsigned, high 32)  ===========
    # ======================================================

    mulhsu x17, x12, x9               # -42 * 7u -> high=0xFFFFFFFF
    mulhsu x18, x4,  x2               # INT_MIN * 2u -> high=0xFFFFFFFF
    mulhsu x19, x11, x9               # 42 * 7u -> high=0x00000000
    mulhsu x20, x3,  x4               # (-1) * 0x80000000u -> high=0xFFFFFFFF
    mulhsu x21, x4,  x4               # INT_MIN * 0x80000000u -> high=0xC0000000

    # More mixed-sign sanity
    mulhsu x22, x13, x2               # 123 * 2u -> high=0
    mulhsu x23, x14, x2               # -123 * 2u -> high=0xFFFFFFFF


halt:
    slti x0, x0, -256                # harmless "halt" (writes to x0)