    .align  4
    .option norvc
    .globl  _start

    .section .data
    .balign 16
buf:    .space 64              # 64 bytes to play with (safe-aligned)

    .section .text
_start:
    # ---- base pointer ----
    lui   x1, %hi(buf)
    addi  x1, x1, %lo(buf)     # x1 = &buf

    ################################################################
    # 1 Base pattern stores (W/H/B) and loads
    ################################################################
    # W stores @0,4
    lui   x2, 0x11112          # 0x11112000
    addi  x2, x2, 0x222        # 0x11112222
    sw    x2, 0(x1)

    lui   x3, 0x33334          # 0x33334000
    addi  x3, x3, 0x444        # 0x33334444
    sw    x3, 4(x1)

    # H/B stores @8,10,11
    li    x4, 0x5555
    sh    x4, 8(x1)

    li    x5, 0x66
    sb    x5, 10(x1)

    li    x6, 0x77
    sb    x6, 11(x1)

    # Loads back (sign and zero-extend coverage)
    lw    x10, 0(x1)           # expect 0x11112222
    lw    x11, 4(x1)           # expect 0x33334444
    lh    x12, 8(x1)           # expect 0x00005555
    lhu   x13, 8(x1)           # expect 0x00005555
    lb    x14, 10(x1)          # expect 0xFFFFFF66
    lbu   x15, 10(x1)          # expect 0x00000066
    lb    x16, 11(x1)          # expect 0xFFFFFF77
    lbu   x17, 11(x1)          # expect 0x00000077

    # Combine for section-1 signature (x24)
    add   x18, x10, x11
    add   x19, x12, x13
    add   x20, x14, x15
    add   x21, x16, x17
    add   x22, x18, x19
    add   x23, x20, x21
    add   x24, x22, x23        # sig1 in x24

    ################################################################
    # 2 Store→Load forwarding stress at a single word
    #    Repeatedly store different values then immediately load.
    #    Good to verify PCSB forwarding logic.
    ################################################################
    # x1 still = &buf
    li    x25, 0              # loop counter
    li    x26, 100            # NUM_ITERS (adjust up to stress more)

store_fwd_loop:
    # value = loop counter * 4 + constant
    slli  x27, x25, 2         # x27 = i * 4
    addi  x27, x27, 0x5A      # add some pattern

    sw    x27, 16(x1)         # store to buf[16..19]
    lw    x28, 16(x1)         # load back immediately

    # check (branch will be mispredicted, but Spike/DUT must agree)
    bne   x27, x28, store_fwd_bad

    addi  x25, x25, 1
    blt   x25, x26, store_fwd_loop

    j     store_fwd_done

store_fwd_bad:
    # Put a recognizable error code into x24
    li    x24, 0xDEADBEEF
    j     store_fwd_done

store_fwd_done:

    ################################################################
    # 3 Store stream over a region (buffer-occupancy stress)
    #    Many back-to-back stores to fill PCSB.
    #    With PCSB off, commit will stall more often.
    ################################################################
    # We'll repeatedly write a 32-byte region [32..63] with a pattern.
    # ENTRIES=8 → 8 consecutive stores here are ideal to stress it.

    li    x29, 0              # outer loop counter
    li    x30, 50             # number of outer iterations (increase to stress more)

store_stream_outer:
    # Inner: write 8 words (32 bytes) in a row
    li    x5, 0               # inner index (0..7)

store_stream_inner:
    # addr = buf + 32 + 4*i
    slli  x6, x5, 2           # x6 = i * 4
    addi  x6, x6, 32          # offset within buf
    add   x7, x1, x6          # effective address

    # pattern = (outer<<16) | inner
    slli  x8, x29, 16
    or    x8, x8, x5

    sw    x8, 0(x7)           # store pattern

    addi  x5, x5, 1
    blt   x5, x0, .Lnever     # dummy to keep label unique
    blt   x5, x31, store_stream_inner

    addi  x29, x29, 1
    blt   x29, x30, store_stream_outer

    ################################################################
    # 4 Independent byte-lane stress @32..35 (your original idea)
    ################################################################
    # This is another good one, so I’ll leave it (slightly cleaned).

    # Write bytes: 32:0x12, 33:0x34, 34:0x56, 35:0x78 -> word 0x78563412
    li    x2,  0x12
    sb    x2,  32(x1)
    li    x3,  0x34
    sb    x3,  33(x1)
    li    x4,  0x56
    sb    x4,  34(x1)
    li    x5,  0x78
    sb    x5,  35(x1)

    lw    x6, 32(x1)          # expect 0x78563412

    ################################################################
    # HALT sentinel – whatever your testbench uses
    ################################################################
    slti  x0, x0, -256        # your existing sentinel
.Lnever:
