    .align  4
    .option norvc
    .globl  _start

    .section .data
    .balign 16
    buf:    .space 32          # 32 bytes we can safely read/write

    .section .text

_start:
    # ---- initialize base pointer and store values ----
    lui   x1, %hi(buf)
    addi  x1, x1, %lo(buf)
    lui   x2, 0x11112         # upper 20 bits
    addi  x2, x2, 0x222       # low 12 (signed) -> 0x11112000 + 0x222 = 0x1111222  
    sw   x2, 0(x1)
    lui   x3, 0x33334
    addi  x3, x3, 0x444
    sw   x3, 4(x1)             # store word at base+4
    li   x4, 0x5555
    sh   x4, 8(x1)             # store halfword at base+8
    li   x5, 0x66
    sb   x5, 10(x1)            # store byte at base+10
    li   x6, 0x77
    sb   x6, 11(x1)            # store byte at base+11

    # ---- load the stored values back ----
    lw   x10, 0(x1)            # expect 0x11112222
    lw   x11, 4(x1)            # expect 0x33334444
    lh   x12, 8(x1)            # expect 0x00005555 (sign-extended)
    lhu  x13, 8(x1)            # expect 0x00005555
    lb   x14, 10(x1)           # expect 0xFFFFFF66 (sign-extended)
    lbu  x15, 10(x1)           # expect 0x00000066
    lb   x16, 11(x1)           # expect 0xFFFFFF77
    lbu  x17, 11(x1)           # expect 0x00000077

    # ---- combine results to detect issues ----
    add  x18, x10, x11
    add  x19, x12, x13
    add  x20, x14, x15
    add  x21, x16, x17
    add  x22, x18, x19
    add  x23, x20, x21
    add  x24, x22, x23        # accumulates all load results

    # ---- HALT sentinel ----
    slti x0, x0, -256