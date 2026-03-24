.option norvc
.globl _start
.section .data
.balign 32
buf: .space 256         # enough space

.section .text
_start:
  lui  x1,%hi(buf)
  addi x1,x1,%lo(buf)

  li   x2,0x01020304

  # 40 stores -> forces orders 0..39
  sw   x2, 0(x1)
  sw   x2, 4(x1)
  sw   x2, 8(x1)
  sw   x2,12(x1)
  sw   x2,16(x1)
  sw   x2,20(x1)
  sw   x2,24(x1)
  sw   x2,28(x1)
  sw   x2,32(x1)
  sw   x2,36(x1)
  sw   x2,40(x1)
  sw   x2,44(x1)
  sw   x2,48(x1)
  sw   x2,52(x1)
  sw   x2,56(x1)
  sw   x2,60(x1)
  sw   x2,64(x1)
  sw   x2,68(x1)
  sw   x2,72(x1)
  sw   x2,76(x1)
  sw   x2,80(x1)
  sw   x2,84(x1)
  sw   x2,88(x1)
  sw   x2,92(x1)
  sw   x2,96(x1)
  sw   x2,100(x1)
  sw   x2,104(x1)
  sw   x2,108(x1)
  sw   x2,112(x1)
  sw   x2,116(x1)
  sw   x2,120(x1)
  sw   x2,124(x1)   # this retire has order 31
  sw   x2,128(x1)   # this retire has order 32 -> where you saw 0
  sw   x2,132(x1)
  sw   x2,136(x1)
  sw   x2,140(x1)
  sw   x2,144(x1)
  sw   x2,148(x1)
  sw   x2,152(x1)

  slti x0,x0,-256
