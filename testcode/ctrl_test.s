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

# li   x1, 1
    li   x2, 2
    beq  x1, x2, 1f            # NOT taken
    addi x30, x30, 1           # executes (marker)
1:

# Taken branch (must flush the next instruction)
    li   x1, 5
    li   x2, 5
    beq  x1, x2, 2f            # TAKEN → redirect
ctrl_poison_taken:
    addi x31, x31, 1           # *** MUST be flushed; should NOT commit ***
2:

# JAL then JALR using the link
    jal  x4, 3f                # x4 = PC+4; jump to 3f
ctrl_poison_skipped_once:
    addi x7, x7, 1             # skipped the first time
3:
    addi x6,x6, 1            # jump to link (PC+4), executes the line above once
    addi x6, x0, 0
    addi x4, x4, 8
    beqz x4, 4f             # jump to HALT (safe forward jump)

    mul x3, x7, x2
    mul x4, x5, x7
    sltu x19, x4, x3 
    
4:  
    add x2, x3, x3

# ---------- HALT sentinel ----------
halt:
    slti x0, x0, -256          # stop/exit for your testbench
