    .align  4
    .section .text
    .globl  _start
    .option norvc

# ==========================================================
# RV32IM Out-of-Order Core Stress Test (no AUIPC)
# - Includes NOP padding and a HALT sentinel
# - Avoids out-of-range immediates (I-type is -2048..+2047)
# ==========================================================

_start:

# ---------- Init registers with varied values ----------
    li   x1,   1
    li   x2,  -2
    li   x3,   3
    li   x4,  -4
    li   x5,   5
    li   x6,  0x00000080        # 128
    li   x7,  0x7FFFFFFF        # INT_MAX
    li   x8,  0x80000000        # INT_MIN
    li   x9,  9
    li   x10, 10
    li   x11, 11
    li   x12, 12
    li   x13, 13
    li   x14, 14
    li   x15, 15
    li   x16, -16
    li   x17, 17
    li   x18, 18
    li   x19, 19
    li   x20, 20
    li   x21, 21
    li   x22, 22
    li   x23, 23
    li   x24, 24
    li   x25, 25
    li   x26, 26
    li   x27, 27
    li   x28, 28
    li   x29, 29
    li   x30, 30
    li   x31, 31

    nop; nop; nop; nop; nop

# ---------- ALU-Immediate: boundaries & sign-extension ----------
# I-immediates are sign-extended 12-bit (-2048..+2047).

    addi x5,  x5,   0          # no-op addi
    addi x6,  x6,  -1          # decrement
    addi x7,  x7,  -2048       # min immediate
    addi x9,  x9,   2047       # max immediate

    xori x10, x10,  0          # XOR with zero
    xori x11, x11, -1          # invert all bits
    xori x30, x30,  0x7FF      # +2047

    andi x12, x12,  0x7FF      # keep low 11 bits
    andi x29, x29,  0x001      # isolate bit 0

    # For ORI with bit 11 set only, use sign-extended -2048 (0xFFFFF800)
    ori  x28, x28, -2048       # exercises sign-extension boundary
    ori  x31, x6,   0x0FF      # dest = x31 (tests your former stall), imm in-range

# ---------- Shift-immediates (shamt 0..31) ----------
    slli x13, x13, 31          # left shift by 31
    srli x14, x14, 31          # logical right by 31
    srai x15, x15, 31          # arithmetic right by 31 (sign-propagate)

    nop; nop

# ---------- ALU-Register (var shifts use rs2&0x1F) ----------
    add  x20, x1,  x2
    sub  x21, x2,  x1
    xor  x22, x3,  x4
    or   x23, x5,  x6
    and  x24, x7,  x8
    sll  x25, x6,  x11         # 128 << (11&31)
    srl  x26, x7,  x12         # INT_MAX >> (12&31)
    sra  x27, x8,  x13         # INT_MIN >> (13&31) arithmetic
    slt  x18, x4,  x3          # signed compare
    sltu x19, x4,  x3          # unsigned compare

    nop

# ---------- Write attempts to x0 (should have no effect) ----------
    addi x0, x1, 123
    or   x0, x2, x3
    slli x0, x0, 1

    nop

# ---------- RAW hazards (back-to-back deps) ----------
    mul  x16, x1, x2           # x16 = 1 * (-2) = -2
    add  x17, x16, x3          # x17 depends on x16
    sub  x18, x17, x16         # x18 depends on x17 & x16

    nop

# ---------- WAW hazard (same dest twice quickly) ----------
    xor  x22, x10, x11
    add  x22, x22, x12         # overwrites x22 before first commits

    nop

# ---------- WAR flavor: later write to src of earlier op ----------
    add  x23, x5,  x6          # reads x5
    and  x5,  x5,  x7          # writes x5 afterward (no true WAR in regs, but stresses rename)

    nop; nop

# ---------- Multiply family (M extension) ----------
# Choose mixed signs to exercise MULH*/MULHU paths too.

    li   x1,  0x00012345
    li   x2,  0xFFFEDCBA       # negative
    mul  x3,  x1,  x2          # low 32
    mulh x4,  x1,  x2          # high (signed*signed)
    mulhsu x5, x2,  x1         # high (signed*unsigned)
    mulhu x6,  x1,  x1         # high (unsigned*unsigned)

    # Back-to-back dependent muls
    mul  x7,  x3,  x1          # uses prior mul low
    mulh x8,  x7,  x2          # dependent high

    nop; nop

# ---------- Divide family (M extension) ----------
# Spec edge cases:
# - DIV by 0 => -1 ; DIVU by 0 => 0xFFFFFFFF
# - REM by 0 => dividend ; REMU by 0 => dividend
# - Overflow: (-2^31)/(-1) => quotient = -2^31 ; remainder = 0

    li   x9,  123456789
    li   x10, -98765
    li   x11, 0

    div   x12, x9,  x10        # mixed sign
    divu  x13, x9,  x6         # unsigned divide by prior mulhu result (likely >0)

    div   x14, x9,  x11        # divide by zero (-> -1)
    divu  x15, x9,  x11        # divide by zero (-> 0xFFFFFFFF)

    rem   x16, x9,  x11        # remainder by zero (-> dividend)
    remu  x17, x9,  x11        # remainder by zero (-> dividend)

    # Overflow case: INT_MIN / -1
    li    x18, 0x80000000      # INT_MIN
    li    x19, -1
    div   x20, x18, x19        # -> 0x80000000
    rem   x21, x18, x19        # -> 0

    # Back-to-back dependent div/rem
    div   x22, x9,  x3         # depends on earlier mul low in x3
    rem   x23, x9,  x22        # depends on quotient

    nop; nop

# ---------- More immediates & shifts to intermix FU pressure ----------
    slti  x24, x2,  -1         # -2 < -1 -> 1
    sltiu x25, x2,   5         # unsigned compare
    slli  x26, x26,  1
    srli  x27, x27,  1
    srai  x28, x28,  1

    xori  x29, x29,  0x55
    andi  x30, x30,  0x3FF
    ori   x31, x31,  0x0AA     # again write to x31

    nop; nop; nop

# ---------- Register shifts with large rs2 (masked to 0..31) ----------
    li    x4,  0x000001F3      # 499 -> masked to 499&31 = 19
    sll   x5,  x5,  x4
    srl   x6,  x6,  x4
    sra   x7,  x7,  x4

    nop; nop

# ---------- More RAW chains across mixed FUs ----------
    mul   x8,  x5,  x6
    divu  x9,  x8,  x10
    remu  x10, x9,  x1
    add   x11, x10, x9
    sub   x12, x11, x8

    nop; nop; nop; nop; nop

# ---------- Final pads ----------
    addi  x1,  x1,  1
    addi  x2,  x2, -1
    xor   x3,  x3,  x3
    or    x4,  x4,  x0
    and   x5,  x5,  x5

    nop; nop; nop

# ---------- HALT sentinel ----------
halt:
    slti x0, x0, -256          # stop/exit for your testbench
