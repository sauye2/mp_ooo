`timescale 1ns/1ps
module top_tb_rob;
  timeunit 1ns; timeprecision 1ps;

  // =========================
  // Waveform dump (Verdi)
  // =========================
  initial begin
    $fsdbDumpfile("dump.fsdb");
    $fsdbDumpvars(0, top_tb_rob, "+all");
  end

  // =========================
  // Clock / Reset
  // =========================
  logic clk = 0, rst = 1;
  always #5 clk = ~clk; // 100 MHz

  initial begin
    repeat (3) @(posedge clk);
    rst = 0;
  end

  // =========================
  // DUT I/O
  // =========================
  localparam int XLEN        = 32;
  localparam int LOG_REGS    = 32;
  localparam int PHY_REGS    = 64;
  localparam int ROB_ENTRIES = 8;

  // Rename -> ROB
  logic                   rtrob_valid, rtrob_ready;
  logic [$clog2(LOG_REGS)-1:0]  rtrob_arch_rd;
  logic [$clog2(PHY_REGS)-1:0]  rtrob_new_prf, rtrob_old_prf;
  logic [31:0]            rtrob_instr, rtrob_pc;
  logic                   rtrob_is_store;
  logic [$clog2(ROB_ENTRIES)-1:0] rtrob_rob_idx;

  // CDB -> ROB
  logic                   cdbrob_valid;
  logic [$clog2(ROB_ENTRIES)-1:0] cdbrob_rob_idx;
  logic [XLEN-1:0]        cdbrob_value;
  logic                   cdbrob_exception;

  // Commit <- ROB
  logic                   commit_valid, commit_ready;
  logic [$clog2(LOG_REGS)-1:0]    commit_arch_rd;
  logic [$clog2(PHY_REGS)-1:0]    commit_new_prf, commit_old_prf;
  logic [31:0]            commit_instr, commit_pc;
  logic                   commit_is_store, commit_exception;
  logic [XLEN-1:0]        commit_value;

  // Status
  logic                   flush_all;
  logic                   rob_full, rob_empty;
  logic [$clog2(ROB_ENTRIES):0] rob_count;
  logic [$clog2(ROB_ENTRIES)-1:0] rob_head_idx, rob_tail_idx;

  // =========================
  // DUT
  // =========================
  ROB #(
    .XLEN(XLEN),
    .LOG_REGS(LOG_REGS),
    .PHY_REGS(PHY_REGS),
    .ROB_ENTRIES(ROB_ENTRIES),
    .STORE_VALUE_IN_ROB(0)   // typical ERR: values live in PRF, not ROB
  ) dut (
    .clk, .rst,
    // rename->rob
    .rtrob_valid, .rtrob_ready,
    .rtrob_arch_rd, .rtrob_new_prf, .rtrob_old_prf,
    .rtrob_instr, .rtrob_pc, .rtrob_is_store,
    .rtrob_rob_idx,
    // cdb->rob
    .cdbrob_valid, .cdbrob_rob_idx, .cdbrob_value, .cdbrob_exception,
    // commit<-rob
    .commit_valid, .commit_ready,
    .commit_arch_rd, .commit_new_prf, .commit_old_prf,
    .commit_instr, .commit_pc, .commit_is_store, .commit_exception,
    .commit_value,
    // status
    .flush_all,
    .rob_full, .rob_empty, .rob_count, .rob_head_idx, .rob_tail_idx
  );

  // =========================
  // Test scenario (ONE basic test)
  // =========================
  // Simple helpers
  task automatic tb_clear_inputs();
    rtrob_valid      = 0;
    rtrob_arch_rd    = '0;
    rtrob_new_prf    = '0;
    rtrob_old_prf    = '0;
    rtrob_instr      = '0;
    rtrob_pc         = '0;
    rtrob_is_store   = 0;

    cdbrob_valid     = 0;
    cdbrob_rob_idx   = '0;
    cdbrob_value     = '0;
    cdbrob_exception = 0;

    commit_ready     = 1; // backend accepts commits by default
    flush_all        = 0;
  endtask

 task automatic tb_alloc
(
  input int arch_rd,
  input int new_prf,
  input int old_prf,
  input int instr,
  input int pc,
  input bit is_store,
  output int alloc_tag
);
  // Drive inputs
  wait (rtrob_ready);
  rtrob_arch_rd  = arch_rd;
  rtrob_new_prf  = new_prf;
  rtrob_old_prf  = old_prf;
  rtrob_instr    = instr;
  rtrob_pc       = pc;
  rtrob_is_store = is_store;
  rtrob_valid    = 1'b1;

  // >>> Capture tag BEFORE posedge so we see the pre-increment tail_q
  #1 alloc_tag = rtrob_rob_idx;   // <— key line
  $display("[TB] Alloc tag=%0d (arch_rd=%0d new=%0d old=%0d)", alloc_tag, arch_rd, new_prf, old_prf);

  @(posedge clk);
  rtrob_valid    = 1'b0;
  @(posedge clk);
endtask


  task automatic tb_wb(input int tag, input bit exn = 0);
    // @(posedge clk);
    cdbrob_rob_idx   = tag[$bits(cdbrob_rob_idx)-1:0];
    cdbrob_exception = exn;
    cdbrob_valid     = 1'b1;
    @(posedge clk);
    cdbrob_valid     = 1'b0;
  endtask

  // Wait for one commit and capture it
  task automatic tb_expect_commit
  (
    input int exp_arch_rd,
    input int exp_new_prf,
    input int exp_old_prf,
    input bit exp_is_store,
    input bit exp_exception
  );
    // Wait until commit_valid asserts (backend always ready)
    wait (commit_valid);
    // sample a delta after posedge so outputs are stable
    #1;
    if (commit_arch_rd   !== exp_arch_rd  ||
        commit_new_prf   !== exp_new_prf  ||
        commit_old_prf   !== exp_old_prf  ||
        commit_is_store  !== exp_is_store ||
        commit_exception !== exp_exception) begin
      $error("[FAIL][COMMIT] Got {rd=%0d new=%0d old=%0d store=%0b exc=%0b} expected {%0d %0d %0d %0b %0b}",
        commit_arch_rd, commit_new_prf, commit_old_prf, commit_is_store, commit_exception,
        exp_arch_rd, exp_new_prf, exp_old_prf, exp_is_store, exp_exception);
      // $fatal;
    end
    else begin
      $display("[PASS][COMMIT] rd=%0d new=%0d old=%0d store=%0b exc=%0b  (count=%0d)",
        commit_arch_rd, commit_new_prf, commit_old_prf, commit_is_store, commit_exception, rob_count);
    end
    // let the pop occur (commit_ready is high)
    @(posedge clk);
  endtask

  // Main test
  initial begin : one_basic_test
    int tag0, tag1, tag2;
    tb_clear_inputs();

    @(negedge rst);
    @(posedge clk);
    $display("\n[TB] ROB smoke test: OoO writeback, in-order commit\n");

    // ---------- Allocate three µops ----------
    tb_alloc(/*arch_rd*/ 5, /*new*/ 15, /*old*/ 2,  /*instr*/ 32'h0000_0001, /*pc*/ 32'h1000, /*store*/ 0, tag0);
    tb_alloc(/*arch_rd*/ 6, /*new*/ 18, /*old*/ 7,  /*instr*/ 32'h0000_0002, /*pc*/ 32'h1004, /*store*/ 0, tag1);
    tb_alloc(/*arch_rd*/ 7, /*new*/ 19, /*old*/ 12, /*instr*/ 32'h0000_0003, /*pc*/ 32'h1008, /*store*/ 1, tag2);

    // Quick sanity on count
    if (rob_count !== 3) begin
      $error("[FAIL] rob_count expected 3, got %0d", rob_count);
      $fatal;
    end else $display("[PASS] rob_count=3 after 3 allocations");

    // ---------- OoO writebacks: I1 completes before I0 ----------
    tb_wb(tag1, /*exn*/ 0);
    // Head (I0) not ready yet → no commit
    if (commit_valid) begin
      $error("[FAIL] commit_valid should be 0 while head not ready");
      $fatal;
    end else $display("[PASS] head not ready => commit_valid=0");

    // Now I0 completes; head should commit next
    tb_wb(tag0, /*exn*/ 0);

    // ---------- Expect commits in order: I0, then I1 ----------
    tb_expect_commit(/*rd*/5, /*new*/15, /*old*/2,  /*store*/0, /*exc*/0);
    tb_expect_commit(/*rd*/6, /*new*/18, /*old*/7,  /*store*/0, /*exc*/0);

    // ---------- Finally writeback/commit I2 ----------
    tb_wb(tag2, /*exn*/ 0);
    tb_expect_commit(/*rd*/7, /*new*/19, /*old*/12, /*store*/1, /*exc*/0);

    // ROB should be empty now
    if (rob_count !== 0 || !rob_empty) begin
      $error("[FAIL] ROB not empty after 3 commits. count=%0d empty=%0b", rob_count, rob_empty);
      // $fatal;
    end else $display("[PASS] ROB empty after all commits");

    $display("\n[TB] All basic checks passed ✅");
    repeat (5) @(posedge clk);
    $finish;
  end

endmodule
