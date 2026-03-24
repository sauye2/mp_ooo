    .align  4
    .section .text
    .globl  _start
    .option norvc

# ==========================================================
# RV32IM Branch Behavior Test (No Jumps)
# - Includes NOP padding and HALT sentinel
# - Only ALU + Load/Store + Branch instructions
# - Avoids out-of-range immediates
# ==========================================================

_start:

# ---------- Init registers with varied values ----------
    li   x1,   1
    li   x2,  -2
    li   x3,   3
    li   x4,  -4
    li   x5,   5
    li   x6,   6
    li   x7,   7
    li   x8,   8
    li   x9,   9
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

    nop; nop; nop; nop; nop #36


# ==========================================================
#   Branch 1: NOT TAKEN
# ==========================================================
    li   x1, 1
    li   x2, 2
    beq  x1, x2, 1f            # NOT taken
    addi x30, x30, 1           # executes (marker) - 40
1:


# ==========================================================
#   Branch 2: TAKEN (simple equality)
# ==========================================================
    li   x3,  5
    li   x4,  5
    beq  x3, x4, 2f            # TAKEN → skip next - 43
    addi x31, x31, 1           # MUST be flushed (not committed)
ctrl_skip1:
2:
    addi x10, x10, 3           # marker: should run once - 44


# ==========================================================
#   Load/Store + Branch using loaded value
# ==========================================================
    #lui  x8, %hi(buf)
    #addi x8, x8, %lo(buf)
    #sw   x5, 0(x8)             # store 5 at buf #46
    #lw   x9, 0(x8)             # load → x9 = 5 #47

    beq  x9, x5, 3f            # TAKEN - #48
    addi x29, x29, 99          # ПОISON — should not retire
    addi x11, x11, 1           # marker - #49


# ==========================================================
#   Less Than / Greater Than branches (mixed)
# ==========================================================
3:
# BLT: -16 < 20 → TAKEN
    blt  x16, x20, 4f
    addi x28, x28, 10          # POISON (must not commit)
4:
    #addi x12, x12, 2           # marker

# BGE: 18 ≥ 10 → TAKEN? Yes.  
# BUT we test NOT TAKEN by flipping values
    #li   x18, 5
    #li   x10, 10
    bge  x18, x18, 5f          # NOT taken
    addi x27, x27, 1           # executes
5:


# ==========================================================
#   Unsigned branch test (BLTU / BGEU)
# ==========================================================

# BLTU: 1 < 0x80000000 → TAKEN
    bltu x1, x8, 6f
    addi x26, x26, 7           # POISON
    add x27, x26, x0
    addi x18, x19, 0
    mul x18, x20, x24
    div x4,x3,x2
6:
    addi x13, x13, 4           # marker


# ==========================================================
#   Final ALU mixing (simple sanity)
# ==========================================================
    add  x14, x11, x12
    xor  x15, x14, x13
    slt  x21, x14, x15


# ==========================================================
# -------------------- HALT sentinel -----------------------
# ==========================================================
halt:
    slti x0, x0, -256           # halt for TB
    beq  x0, x0, halt           # backup halt loop


# ==========================================================
# ---------------------- Data section ----------------------
# ==========================================================
    .section .data
    .balign 16
buf:
    .word 0
