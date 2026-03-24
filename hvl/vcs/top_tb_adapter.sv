`timescale 1ns/1ps
module top_tb_adapter;
  timeunit 1ns; timeprecision 1ps;

  initial begin
    $fsdbDumpfile("dump.fsdb");
    $fsdbDumpvars(0, top_tb_adapter, "+all");
  end

  logic clk = 0, rst = 1;
  always #5 clk = ~clk; // 100 MHz
  initial begin
    repeat (3) @(posedge clk);
    rst = 0;
  end

  // -------- DUT I/O --------
  logic [31:0]  dfp_addr;
  logic         dfp_read;
  logic [255:0] dfp_rdata;
  logic         dfp_resp;

  logic [31:0]  bmem_addr, bmem_raddr;
  logic         bmem_read;
  logic [63:0]  bmem_rdata;
  logic         bmem_rvalid;
  logic         bmem_ready;

  cacheline_adapter dut (
    .clk, .rst,
    .dfp_addr, .dfp_read, .dfp_rdata, .dfp_resp,
    .bmem_addr, .bmem_read,
    .bmem_rdata, .bmem_rvalid, .bmem_ready
  );

  // -------- Minimal-latency DRAM model (no bubbles) --------
  // Handshake: one-cycle ready when request observed
  logic seen_req;
  assign bmem_ready = bmem_read && !seen_req;

  // 4-beat burst begins the cycle AFTER handshake
  logic        burst_active;
  logic [1:0]  beat;

  logic [63:0] BEAT0 = 64'hAA00_0000_0000_0000;
  logic [63:0] BEAT1 = 64'hBB11_1111_1111_1111;
  logic [63:0] BEAT2 = 64'hCC22_2222_2222_2222;
  logic [63:0] BEAT3 = 64'hDD33_3333_3333_3333;

  always_ff @(posedge clk) begin
    if (rst) begin
      seen_req     <= 1'b0;
      burst_active <= 1'b0;
      beat         <= '0;
      bmem_rvalid  <= 1'b0;
      bmem_rdata   <= '0;
      bmem_raddr   <= '0;
    end else begin
      // track handshake
      if (bmem_read && bmem_ready) seen_req <= 1'b1;
      else if (!bmem_read)         seen_req <= 1'b0;

      bmem_rvalid <= 1'b0;

      if (bmem_read && bmem_ready) begin
        bmem_raddr   <= bmem_addr;
        burst_active <= 1'b1;
        beat         <= '0;
      end
      else if (burst_active) begin
        bmem_rvalid <= 1'b1;
        unique case (beat)
          2'd0: bmem_rdata <= BEAT0;
          2'd1: bmem_rdata <= BEAT1;
          2'd2: bmem_rdata <= BEAT2;
          2'd3: bmem_rdata <= BEAT3;
          default: bmem_rdata <= '0;
        endcase

        if (beat == 2'd3) burst_active <= 1'b0;
        else              beat <= beat + 2'd1;
      end
    end
  end

  // -------- Stimulus: one 32B line read --------
  initial begin : test_single_read
    logic [255:0] expect_line;
    dfp_addr = 32'h0000_1000;
    dfp_read = 1'b0;

    @(negedge rst);
    @(posedge clk);

    $display("\n[TB] Starting single READ transaction...");
    dfp_read <= 1'b1;
    @(posedge clk);
    dfp_read <= 1'b0;

    wait (dfp_resp);
    #1;
    expect_line = {BEAT3, BEAT2, BEAT1, BEAT0};
    if (dfp_rdata !== expect_line) begin
      $error("[FAIL] Assembled line mismatch!\nGot   = %h\nExpect= %h", dfp_rdata, expect_line);
      $fatal;
    end else begin
      $display("[PASS] Correct 256-bit line assembled:\n%h", dfp_rdata);
    end

    repeat (5) @(posedge clk);
    $finish;
  end
endmodule
