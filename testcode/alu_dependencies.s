alu_dependencies.s:
  .align 4
    .section .text
    .globl _start
_start:
    addi x1, x0,1
    addi x2, x0, 2
    add x3, x1, x2    # both not-ready when dispatched
    addi x0, x0, 0     # ditto
halt:
    slti x0, x0, -256
