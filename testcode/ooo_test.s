.align 4
.section .text
.globl _start
    # This program provides a test for demonstrating OOO-ness in an RV32I processor
    # This test involves multiple arithmetic, logical, and division operations
    # as well as dependency hazards (RAW, WAW, WAR)
    # Only registers x0 to x31 are used

_start:

# initialize values
li x1, 10      # x1 = 10
li x2, 20      # x2 = 20
li x3, 30      # x3 = 30
li x4, 40      # x4 = 40
li x5, 50      # x5 = 50
li x6, 60      # x6 = 60
li x7, 70      # x7 = 70
li x8, 80      # x8 = 80
li x9, 90      # x9 = 90
li x10, 100    # x10 = 100
li x11, 110    # x11 = 110
li x12, 120    # x12 = 120
li x13, 130    # x13 = 130
li x14, 140    # x14 = 140
li x15, 150    # x15 = 150
li x16, 160    # x16 = 160
li x17, 170    # x17 = 170
li x18, 180    # x18 = 180
li x19, 190    # x19 = 190
li x20, 200    # x20 = 200
li x21, 210    # x21 = 210
li x22, 220    # x22 = 220
li x23, 230    # x23 = 230
li x24, 240    # x24 = 240
li x25, 250    # x25 = 250
li x26, 260    # x26 = 260
li x27, 270    # x27 = 270
li x28, 280    # x28 = 280
li x29, 290    # x29 = 290
li x30, 300    # x30 = 300
li x31, 310    # x31 = 310

nop
nop
nop
nop
nop

# Test 1: RAW hazard (multiplication result used in next instruction)
mul x16, x1, x2        # x16 = x1 * x2 (x16 = 10 * 20 = 200)
add x17, x16, x3       # x17 = x16 + x3 (x17 = 200 + 30 = 230)

# Test 2: WAW hazard (same register written in two different instructions)
mul x18, x4, x5        # x18 = x4 * x5 (x18 = 40 * 50 = 2000)
add x18, x6, x7        # x18 = x6 + x7 (x18 = 60 + 70 = 130)   # WAW hazard on x18

# Test 3: WAR hazard (writing to register after it's read)
mul x19, x8, x9        # x19 = x8 * x9 (x19 = 80 * 90 = 7200)
add x8, x2, x3         # x8 = x2 + x3 (x8 = 20 + 30 = 50)     # WAR hazard on x8

# Test 4: Multiple parallel operations, no dependencies
xor x20, x10, x11      # x20 = x10 ^ x11
sll x21, x12, x13      # x21 = x12 << x13 (120 << 130 should cause overflow)
or x22, x14, x15       # x22 = x14 | x15 (x22 = 140 | 150)

# Test 5: Division and multiplication with dependencies
mul x23, x1, x2        # x23 = x1 * x2 (x23 = 10 * 20 = 200)
div x24, x23, x3       # x24 = x23 / x3 (x24 = 200 / 30 ≈ 6)  # Division after multiplication

# Test 6: More arithmetic and bitwise instructions
sub x25, x5, x6        # x25 = x5 - x6 (x25 = 50 - 60 = -10)
and x26, x7, x8        # x26 = x7 & x8 (x26 = 70 & 80 = 64)
srl x27, x9, x12       # x27 = x9 >> x12 (x27 = 90 >> 120 results in 0)

# Test 7: Multiple instructions and stress test on ALU with hazards
mul x30, x10, x11      # x30 = x10 * x11 (x30 = 100 * 110 = 11000)
div x31, x30, x13      # x31 = x30 / x13 (x31 = 11000 / 130 ≈ 84)

and x5, x5, 0

nop
nop
nop
nop
nop

div x6, x2, x5


halt:
    slti x0, x0, -256  # Stop the test program (exit condition)
