    .section .text
    .globl _start
_start:

    # Call func1, using x1 as link register (rd is link, rs1 !link → Push)
    jal     x1, func1          # returns to after_calls

after_calls:
    j       halt               # once func1 returns, go straight to halt

# func1 calls func2 using x5 as a "link" reg, then returns to after_calls
func1:
    jal     x5, func2          # rd is link (x5), rs1 !link → Push (2nd level)
ret1:
    jalr    x0, x1, 0          # RET via x1 (rs1 is link, rd not link) → Pop

# func2 returns to func1 using x5
func2:
    jalr    x0, x5, 0          # RET via x5 (rs1 is link, rd not link) → Pop

halt:
    slti    x0, x0, -256       # standard “halt” loop
