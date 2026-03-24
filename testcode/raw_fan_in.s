raw_fan_in.s:
.align 4
.section .text
.globl _start
_start:
  #li  x1,  9
  #add x0,  x1, x1          # should be discarded
  #add x2,  x0, x1          # x2 = 0 + 9 = 9

  #mul x0,  x1, x1          # discarded
  #add x3,  x2, x0          # x3 = 9 + 0 = 9

  #li x12, 0x80000000
  #li x10, 1
  #mulh x26, x12, x10      # expect x26 = 0xFFFFFFFF

  # ---- Seeds (constants) ----
    li x1,   7
    li x2,   3
    li x3,  56
    li x4,  12
    li x5,   5
    li x6,   2
    li x7,   9
    li x8,   4
    li x14, 10            # used for WAR producer-read
    addi x31, x0, 0       # known zero if you prefer

    # ----------------------------------------------------------------
    # 1 RAW chain (DIV waits on MUL)
    # ----------------------------------------------------------------
    mul x9,  x1, x2         # x9 = 7*3
    div x10, x9, x5         # RAW: uses x9

    # ----------------------------------------------------------------
    # 2 Both-srcs-not-ready fan-in (two producers -> one consumer)
    # ----------------------------------------------------------------
    mul x11, x3, x6         # producer A
    mul x12, x4, x2         # producer B
    div x13, x11, x12       # waits on BOTH x11 & x12

    # ----------------------------------------------------------------
    # 3 Fan-out (one producer -> two consumers)
    # ----------------------------------------------------------------
    mul x15, x7, x6         # producer C
    div x16, x15, x2        # consumer 1 of x15
    div x17, x15, x5        # consumer 2 of x15

    # ----------------------------------------------------------------
    # 4 WAW on same rd (second write must win)
    # ----------------------------------------------------------------
    mul x18, x1,  x5        # first writer to x18 (PD_A)
    div x18, x3,  x2        # second writer to x18 (PD_B) should be the value seen by later users

    # ----------------------------------------------------------------
    # 5 WAR: producer reads x14, later we WRITE x14 (must NOT affect already-captured read)
    # ----------------------------------------------------------------
    mul x19, x14, x6        # reads old x14
    div x14, x3,  x5        # later write to x14 (rename/new PD for x14)

    # ----------------------------------------------------------------
    # 6 Cross-FU: DIV producer -> MUL consumer
    # ----------------------------------------------------------------
    div x20, x19,  x14        # producer D
    mul x21, x20, x6        # waits on x20

    # ----------------------------------------------------------------
    # 7 Long mixed chain: MUL -> DIV -> MUL
    # ----------------------------------------------------------------
    mul x22, x1,  x3
    div x23, x22, x7
    mul x24, x23, x22

    # ----------------------------------------------------------------
    # 8 Rename-after-write (WAW) then consume latest mapping
    #    Two writes to x25; consumer must depend on the SECOND (latest) PD
    # ----------------------------------------------------------------
    mul x25, x1,  x2        # x25 := PD_A
    div x25, x3,  x6        # x25 := PD_B (latest)
    mul x26, x25, x25        # must wait on PD_B (not PD_A)

    # ----------------------------------------------------------------
    # 9 CDB contention: back-to-back MULs + a DIV that completes nearby
    #    (Exact overlap depends on your latencies; still stresses arbiter.)
    # ----------------------------------------------------------------
    mul x27, x7,  x7
    mul x28, x3,  x5
    mul x29, x28,  x27
    div x30, x22, x29        # arrives amidst/after a burst of MUL completions

    # ----------------------------------------------------------------
    # 10 x0 destination (no PD alloc; ROB must still mark done)
    # ----------------------------------------------------------------
    #div x0,  x3,  x6        # rd==x0 special-case

    # ----------------------------------------------------------------
    # 11 Deep both-srcs-not-ready: two-level producers feeding a consumer
    # ----------------------------------------------------------------
    # Level 1 producers
    mul x5,  x1,  x2        # reuses x5 as a real value now
    mul x6,  x3,  x4        # reuses x6 as a real value now
    # Level 2 producers (depend on level 1)
    div x7,  x5,  x2        # waits on x5
    div x8,  x6,  x1        # waits on x6
    # Fan-in consumer (waits on both x7 and x8)
    mul x9,  x7,  x8


halt:
  slti x0, x0, -256        # expect x2=9, x3=9, x0=0