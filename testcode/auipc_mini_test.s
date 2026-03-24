    .align  4
    .section .text
    .globl  _start
    .option norvc

_start:

# ------------------------------
# Register init (keep your style)
# ------------------------------
    li   x1,   1
    li   x2,  -2
    li   x3,   3
    li   x4,  -4
    li   x5,   5
    li   x6,  0x00000080
    li   x7,  0x7FFFFFFF
    li   x8,  0x80000000
    li   x9,  9

# ==============================
#        LOAD/STORE TEST
# ==============================

# Base pointer to buffer
    la   x20, buf

# ------------------------------------------
# Store some known patterns into the buffer
# ------------------------------------------

    # SW test
    li   x10, 0x11112222
    sw   x10, 0(x20)          # buf[0]

    li   x11, 0x33334444
    sw   x11, 4(x20)          # buf[4]

    # SH test (writes halfword within aligned word)
    li   x12, 0x5555
    sh   x12, 8(x20)          # buf[8..9]

    li   x13, 0x7777
    sh   x13, 10(x20)         # buf[10..11]

    # SB test
    li   x14, 0x88
    sb   x14, 12(x20)         # buf[12]

    li   x15, 0x99
    sb   x15, 13(x20)         # buf[13]

    # Another SW for spacing
    li   x16, 0xAAAABBBB
    sw   x16, 16(x20)

# ------------------------------------------
# Now LOAD THEM BACK in all formats
# ------------------------------------------

    # LW
    lw   x21, 0(x20)          # x21 = 0x11112222
    lw   x22, 4(x20)          # x22 = 0x33334444
    #lw   x23, 16(x20)         # x23 = 0xAAAABBBB

    # LH / LHU
    lh   x24, 8(x20)          # 0x5555 (sign-extended)
    lhu  x25, 8(x20)          # 0x5555 (zero-extended)

    lh   x26, 10(x20)         # 0x7777 (sign-extended)
    lhu  x27, 10(x20)

    # LB / LBU
    lb   x28, 12(x20)         # 0xFFFFFF88
    lbu  x29, 12(x20)         # 0x00000088

    lb   x30, 13(x20)         # 0xFFFFFF99
    lbu  x31, 13(x20)

# ==============================
#             END
# ==============================
slti x0, x0, -256 

# ======================================
#            BUFFER IN TEXT
# ======================================
# MUST appear *after* code so PC never
# executes the data as instructions.
# ======================================

    .balign 16
buf:
    .word 0x00000000    # [0]
    .word 0x00000000    # [4]
    .word 0x00000000    # [8]
    .word 0x00000000    # [12]
    .word 0x00000000    # [16]