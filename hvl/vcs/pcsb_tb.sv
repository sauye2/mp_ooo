module pcsb_tb;

  localparam ENTRIES = 8;

  // Clock / reset
  logic clk;
  logic rst;

  // DUT interface
  logic        enq_valid;
  logic        enq_ready;
  logic [31:0] enq_addr;
  logic [3:0]  enq_wmask;
  logic [31:0] enq_wdata;

  logic [31:0] drain_addr;
  logic [3:0]  drain_wmask;
  logic [31:0] drain_wdata;
  logic        drain_valid;
  logic        drain_ready;
  logic        drain_resp;

  logic [31:0] fwd_addr;
  logic [3:0]  fwd_rmask;
  logic        fwd_full_hit;
  logic        fwd_partial;
  logic [31:0] fwd_data;

  logic        buf_empty;
  logic        buf_full;

  // Instantiate DUT
  pcsb #(.ENTRIES(ENTRIES)) dut (
    .clk         (clk),
    .rst         (rst),

    .enq_valid   (enq_valid),
    .enq_ready   (enq_ready),
    .enq_addr    (enq_addr),
    .enq_wmask   (enq_wmask),
    .enq_wdata   (enq_wdata),

    .drain_addr  (drain_addr),
    .drain_wmask (drain_wmask),
    .drain_wdata (drain_wdata),
    .drain_valid (drain_valid),
    .drain_ready (drain_ready),
    .drain_resp  (drain_resp),

    .fwd_addr    (fwd_addr),
    .fwd_rmask   (fwd_rmask),
    .fwd_full_hit(fwd_full_hit),
    .fwd_partial (fwd_partial),
    .fwd_data    (fwd_data),

    .buf_empty   (buf_empty),
    .buf_full    (buf_full)
  );

  // ========== Scoreboard storage ==========

  typedef struct packed {
    logic [3:0]  wmask;
    logic [31:0] wdata;
  } sb_word_t;

  // "Architectural" memory after commits
  sb_word_t commit_mem [logic [31:0]];

  // What actually drained from PCSB
  sb_word_t pcsb_mem   [logic [31:0]];

  // Shared variables for tasks and tests
  integer k;
  integer b;
  integer wait_cycles;
  integer seed;
  integer num_to_drain;

  // Shared per-test temporaries (declared at module scope to avoid syntax issues)
  logic       enq_ok;
  logic       drain_ok;
  logic       enq_blocked_ok;
  logic [31:0] addr_d;
  logic [3:0]  wmask_d;
  logic [31:0] wdata_d;

  logic [31:0] t3_exp_word;
  logic [31:0] t4_exp_a1, t4_exp_a2, t4_exp_a3;

  logic [31:0] base5, addr5, data5;
  logic [3:0]  mask5;

  logic [31:0] base6, data6;
  logic [3:0]  mask6;

  logic [31:0] base7, t7_exp;

  logic [31:0] base8_a, base8_b, data8;
  logic [3:0]  mask8_a, mask8_b;

  // ========= Clock =========
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  // ========= Helper: reset scoreboard =========
  task automatic clear_scoreboard();
    foreach (commit_mem[addr]) begin
      commit_mem.delete(addr);
    end
    foreach (pcsb_mem[addr]) begin
      pcsb_mem.delete(addr);
    end
  endtask

  // ========= Scoreboard: commit model =========
  task automatic sb_commit_store (
    input logic [31:0] addr,
    input logic [3:0]  wmask,
    input logic [31:0] wdata
  );
    sb_word_t w;
    if (commit_mem.exists(addr)) begin
      w = commit_mem[addr];
    end else begin
      w.wmask = 4'b0000;
      w.wdata = 32'h0;
    end

    for (b = 0; b < 4; b = b + 1) begin
      if (wmask[b]) begin
        w.wmask[b] = 1'b1;
        w.wdata[b*8 +: 8] = wdata[b*8 +: 8];
      end
    end

    commit_mem[addr] = w;
  endtask

  // ========= Scoreboard: PCSB observed store =========
  task automatic sb_pcsb_store (
    input logic [31:0] addr,
    input logic [3:0]  wmask,
    input logic [31:0] wdata
  );
    sb_word_t w;
    if (pcsb_mem.exists(addr)) begin
      w = pcsb_mem[addr];
    end else begin
      w.wmask = 4'b0000;
      w.wdata = 32'h0;
    end

    for (b = 0; b < 4; b = b + 1) begin
      if (wmask[b]) begin
        w.wmask[b] = 1'b1;
        w.wdata[b*8 +: 8] = wdata[b*8 +: 8];
      end
    end

    pcsb_mem[addr] = w;
  endtask

  // ========= Scoreboard compare =========
  task automatic sb_check_equal(input string tag);
    logic mismatch;
    mismatch = 1'b0;

    // Every address in commit_mem must be present and equal in pcsb_mem
    foreach (commit_mem[a]) begin
      if (!pcsb_mem.exists(a)) begin
        $display("  **FAIL** %s scoreboard: missing addr %08h in pcsb_mem", tag, a);
        mismatch = 1'b1;
      end else begin
        if (commit_mem[a].wmask !== pcsb_mem[a].wmask ||
            commit_mem[a].wdata !== pcsb_mem[a].wdata) begin
          $display("  **FAIL** %s scoreboard mismatch addr=%08h exp_wmask=%4b exp_wdata=%08h got_wmask=%4b got_wdata=%08h",
                   tag, a,
                   commit_mem[a].wmask, commit_mem[a].wdata,
                   pcsb_mem[a].wmask, pcsb_mem[a].wdata);
          mismatch = 1'b1;
        end
      end
    end

    // No extra addresses in pcsb_mem
    foreach (pcsb_mem[a]) begin
      if (!commit_mem.exists(a)) begin
        $display("  **FAIL** %s scoreboard: extra addr %08h in pcsb_mem", tag, a);
        mismatch = 1'b1;
      end
    end

    if (!mismatch) begin
      $display("  PASS  %s scoreboard: commit_mem and pcsb_mem match", tag);
    end
  endtask

  // ========= Debug dump of DUT state =========
  task automatic display_state(input string tag);
    $display("    [%s] count=%0d head=%0d tail=%0d empty=%0d full=%0d",
             tag, dut.count_q, dut.head_q, dut.tail_q, buf_empty, buf_full);
    for (k = 0; k < ENTRIES; k = k + 1) begin
      $display("      entry %0d: valid=%0d addr=%08h wmask=%4b wdata=%08h",
               k,
               dut.entries_q[k].valid,
               dut.entries_q[k].addr,
               dut.entries_q[k].wmask,
               dut.entries_q[k].wdata);
    end
  endtask

  // ========= Enqueue store (with expectation) =========
  task automatic do_enq_store (
    input  string       name,
    input  logic [31:0] addr,
    input  logic [3:0]  wmask,
    input  logic [31:0] wdata,
    input  logic        expect_success,
    output logic        enq_fired
  );
    enq_fired = 1'b0;

    enq_addr  <= addr;
    enq_wmask <= wmask;
    enq_wdata <= wdata;
    enq_valid <= 1'b1;

    wait_cycles = 0;
    while (wait_cycles < 32) begin
      @(posedge clk);
      if (enq_ready) begin
        $display("  ENQ  %-10s addr=%08h wmask=%4b wdata=%08h cycle=%0t",
                 name, addr, wmask, wdata, $time/10);
        enq_fired = 1'b1;
        break;
      end
      wait_cycles = wait_cycles + 1;
    end

    if (!enq_fired) begin
      if (expect_success) begin
        $display("  **FAIL** ENQ %-10s no handshake in 32 cycles (buf_full=%0d)",
                 name, buf_full);
      end else begin
        $display("  PASS  ENQ %-10s correctly blocked (buf_full=%0d)",
                 name, buf_full);
      end
    end else if (!expect_success) begin
      $display("  **FAIL** ENQ %-10s fired but was expected to be blocked", name);
    end

    enq_valid <= 1'b0;
    enq_addr  <= 32'h0;
    enq_wmask <= 4'h0;
    enq_wdata <= 32'h0;
  endtask

  // ========= Drain one store (with expectation) =========
  task automatic do_drain_one (
    input  string       name,
    input  logic        expect_success,
    output logic        got_drain,
    output logic [31:0] addr,
    output logic [3:0]  wmask,
    output logic [31:0] wdata
  );
    got_drain = 1'b0;
    addr      = 32'h0;
    wmask     = 4'h0;
    wdata     = 32'h0;

    wait_cycles = 0;
    while (wait_cycles < 32) begin
      @(posedge clk);
      if (drain_valid) begin
        addr  = drain_addr;
        wmask = drain_wmask;
        wdata = drain_wdata;

        $display("  DRAIN %-10s addr=%08h wmask=%4b wdata=%08h cycle=%0t",
                 name, addr, wmask, wdata, $time/10);

        drain_ready <= 1'b1;
        @(posedge clk);
        drain_ready <= 1'b0;

        drain_resp <= 1'b1;
        @(posedge clk);
        drain_resp <= 1'b0;

        got_drain = 1'b1;
        break;
      end
      wait_cycles = wait_cycles + 1;
    end

    if (expect_success && !got_drain) begin
      $display("  **FAIL** DRAIN %-10s no drain_valid in 32 cycles (buf_empty=%0d count=%0d)",
               name, buf_empty, dut.count_q);
    end else if (!expect_success && got_drain) begin
      $display("  **FAIL** DRAIN %-10s occurred but was not expected", name);
    end
  endtask

  // ========= Forwarding check =========
  task automatic do_forward_check (
    input string       name,
    input logic [31:0] addr,
    input logic [3:0]  rmask,
    input logic        exp_full,
    input logic        exp_partial,
    input logic [31:0] exp_data
  );
    fwd_addr  <= addr;
    fwd_rmask <= rmask;

    @(posedge clk);

    $display("  FWD  %-10s addr=%08h rmask=%4b full=%0d partial=%0d data=%08h exp_full=%0d exp_partial=%0d exp_data=%08h",
             name, addr, rmask, fwd_full_hit, fwd_partial, fwd_data,
             exp_full, exp_partial, exp_data);

    if ((fwd_full_hit !== exp_full) ||
        (fwd_partial  !== exp_partial) ||
        (fwd_data     !== exp_data)) begin
      $display("  **FAIL** FWD %s", name);
    end else begin
      $display("  PASS  FWD %s", name);
    end

    fwd_addr  <= 32'h0;
    fwd_rmask <= 4'h0;
  endtask

  // ========= Main test sequence =========
  initial begin
    $display("\n==== PCSB comprehensive verification (no flush) ====\n");

    rst         = 1'b1;
    enq_valid   = 1'b0;
    enq_addr    = 32'h0;
    enq_wmask   = 4'h0;
    enq_wdata   = 32'h0;
    drain_ready = 1'b0;
    drain_resp  = 1'b0;
    fwd_addr    = 32'h0;
    fwd_rmask   = 4'h0;
    seed        = 32'h1234_5678;

    clear_scoreboard();

    repeat (4) @(posedge clk);
    rst = 1'b0;
    repeat (2) @(posedge clk);

    // ---------------- Test 1: Reset state ----------------
    $display("Test 1: Reset state");
    if (buf_empty && !buf_full && enq_ready && !drain_valid)
      $display("  PASS: buffer empty, not full, enq_ready=1, no drain_valid after reset");
    else
      $display("  **FAIL**: unexpected outputs after reset");

    // ---------------- Test 2: Single store ----------------
    $display("\nTest 2: Single store enqueue and drain with scoreboard");

    do_enq_store("T2_S1", 32'h0000_1000, 4'b1111, 32'hA0B0_C0D0, 1'b1, enq_ok);
    if (enq_ok) sb_commit_store(32'h0000_1000, 4'b1111, 32'hA0B0_C0D0);

    @(posedge clk);
    display_state("T2 after enqueue");

    do_drain_one("T2_D1", 1'b1, drain_ok, addr_d, wmask_d, wdata_d);
    if (drain_ok) sb_pcsb_store(addr_d, wmask_d, wdata_d);

    sb_check_equal("T2");

    @(posedge clk);
    display_state("T2 after drain");

    // ---------------- Test 3: Coalescing two stores ----------------
    $display("\nTest 3: Coalescing two stores to same word");
    clear_scoreboard();

    do_enq_store("T3_S1", 32'h0000_2000, 4'b1111, 32'h1122_3344, 1'b1, enq_ok);
    if (enq_ok) sb_commit_store(32'h0000_2000, 4'b1111, 32'h1122_3344);

    do_enq_store("T3_S2", 32'h0000_2000, 4'b1100, 32'hAABB_0000, 1'b1, enq_ok);
    if (enq_ok) sb_commit_store(32'h0000_2000, 4'b1100, 32'hAABB_0000);

    t3_exp_word = 32'hAABB_3344;

    @(posedge clk);
    display_state("T3 after enqueues");
    if (dut.count_q == 1)
      $display("  PASS: count_q==1 after coalescing");
    else
      $display("  **FAIL** T3 count_q=%0d expected 1", dut.count_q);

    do_forward_check("T3_FULL",
                     32'h0000_2000, 4'b1111,
                     1'b1, 1'b0, t3_exp_word);
    do_forward_check("T3_UPPER",
                     32'h0000_2000, 4'b1100,
                     1'b1, 1'b0, t3_exp_word);
    do_forward_check("T3_LOWER",
                     32'h0000_2000, 4'b0011,
                     1'b1, 1'b0, t3_exp_word);

    do_drain_one("T3_DRAIN", 1'b1, drain_ok, addr_d, wmask_d, wdata_d);
    if (drain_ok) sb_pcsb_store(addr_d, wmask_d, wdata_d);

    sb_check_equal("T3");

    @(posedge clk);
    display_state("T3 after drain");

    // ---------------- Test 4: Multiple addresses with coalescing ----------------
    $display("\nTest 4: Multiple addresses with coalescing");
    clear_scoreboard();

    do_enq_store("T4_A1_1", 32'h0000_3000, 4'b0011, 32'h0000_1234, 1'b1, enq_ok);
    if (enq_ok) sb_commit_store(32'h0000_3000, 4'b0011, 32'h0000_1234);

    do_enq_store("T4_A2_1", 32'h0000_3004, 4'b1111, 32'hAAAA_BBBB, 1'b1, enq_ok);
    if (enq_ok) sb_commit_store(32'h0000_3004, 4'b1111, 32'hAAAA_BBBB);

    do_enq_store("T4_A1_2", 32'h0000_3000, 4'b1100, 32'h5678_0000, 1'b1, enq_ok);
    if (enq_ok) sb_commit_store(32'h0000_3000, 4'b1100, 32'h5678_0000);

    do_enq_store("T4_A3_1", 32'h0000_3008, 4'b0101, 32'hC0DE_C0DE, 1'b1, enq_ok);
    if (enq_ok) sb_commit_store(32'h0000_3008, 4'b0101, 32'hC0DE_C0DE);

    t4_exp_a1 = 32'h5678_1234;
    t4_exp_a2 = 32'hAAAA_BBBB;
    t4_exp_a3 = 32'h00DE_00DE;

    @(posedge clk);
    display_state("T4 after enqueues");

    if (dut.count_q == 3)
      $display("  PASS: count_q==3 after coalescing");
    else
      $display("  **FAIL** T4 count_q=%0d expected 3", dut.count_q);

    do_forward_check("T4_A1_FULL",
                     32'h0000_3000, 4'b1111,
                     1'b1, 1'b0, t4_exp_a1);
    do_forward_check("T4_A2_FULL",
                     32'h0000_3004, 4'b1111,
                     1'b1, 1'b0, t4_exp_a2);
    do_forward_check("T4_A3_MASKED",
                     32'h0000_3008, 4'b0101,
                     1'b1, 1'b0, t4_exp_a3);

    do_drain_one("T4_DRAIN", 1'b1, drain_ok, addr_d, wmask_d, wdata_d);
    if (drain_ok) sb_pcsb_store(addr_d, wmask_d, wdata_d);
    do_drain_one("T4_DRAIN", 1'b1, drain_ok, addr_d, wmask_d, wdata_d);
    if (drain_ok) sb_pcsb_store(addr_d, wmask_d, wdata_d);
    do_drain_one("T4_DRAIN", 1'b1, drain_ok, addr_d, wmask_d, wdata_d);
    if (drain_ok) sb_pcsb_store(addr_d, wmask_d, wdata_d);

    sb_check_equal("T4");

    @(posedge clk);
    display_state("T4 after drains");

    // ---------------- Test 5: Buffer full and coalescing behavior ----------------
    $display("\nTest 5: Buffer full and coalescing behavior");
    clear_scoreboard();

    base5 = 32'h0000_4000;
    for (k = 0; k < ENTRIES; k = k + 1) begin
      addr5 = base5 + (k * 4);
      mask5 = 4'b0001 << (k % 4);
      data5 = 32'h1000_0000 + k;

      do_enq_store($sformatf("T5_FILL_%0d", k), addr5, mask5, data5, 1'b1, enq_ok);
      if (enq_ok) sb_commit_store(addr5, mask5, data5);
    end

    @(posedge clk);
    display_state("T5 after fill");

    if (buf_full && (dut.count_q == ENTRIES))
      $display("  PASS: buffer is full after fill");
    else
      $display("  **FAIL** buffer not full after fill (count_q=%0d buf_full=%0d)",
               dut.count_q, buf_full);

    do_enq_store("T5_OVERFLOW", 32'h0000_4FFF, 4'b1111, 32'hFFFF_FFFF, 1'b0, enq_blocked_ok);

    addr5 = base5 + ((ENTRIES-1) * 4);
    mask5 = 4'b0011;
    data5 = 32'hCAFE_BABE;

    // Coalescing at full should be accepted
    do_enq_store("T5_COAL", addr5, mask5, data5, 1'b1, enq_ok);
    if (enq_ok) sb_commit_store(addr5, mask5, data5);

    for (k = 0; k < ENTRIES; k = k + 1) begin
      do_drain_one("T5_DRAIN", 1'b1, drain_ok, addr_d, wmask_d, wdata_d);
      if (drain_ok) sb_pcsb_store(addr_d, wmask_d, wdata_d);
    end

    sb_check_equal("T5");

    @(posedge clk);
    display_state("T5 after drains");

    // ---------------- Test 6: Small random pattern with scoreboard ----------------
    $display("\nTest 6: Small random pattern with scoreboard");
    clear_scoreboard();

    base6 = 32'h0000_500C;

    for (k = 0; k < 16; k = k + 1) begin
      seed  = seed + 32'h9E37_79B9;
      data6 = seed;

      seed  = seed ^ 32'hA5A5_5A5A;
      mask6 = seed[3:0];
      if (mask6 == 4'b0000)
        mask6 = 4'b1111;

      do_enq_store($sformatf("T6_S%0d", k), base6, mask6, data6, 1'b1, enq_ok);
      if (enq_ok) sb_commit_store(base6, mask6, data6);
    end

    @(posedge clk);
    display_state("T6 after enqueues");

    do_drain_one("T6_DRAIN", 1'b1, drain_ok, addr_d, wmask_d, wdata_d);
    if (drain_ok) sb_pcsb_store(addr_d, wmask_d, wdata_d);

    sb_check_equal("T6");

    @(posedge clk);
    display_state("T6 after drain");

    // ---------------- Test 7: Forwarding vs scoreboard (no drains) ----------------
    $display("\nTest 7: Forwarding checks against scoreboard (no drains)");
    clear_scoreboard();

    base7 = 32'h0000_6000;

    do_enq_store("T7_S1", base7, 4'b0101, 32'h1122_3344, 1'b1, enq_ok);
    if (enq_ok) sb_commit_store(base7, 4'b0101, 32'h1122_3344);

    do_enq_store("T7_S2", base7, 4'b1010, 32'h5566_7788, 1'b1, enq_ok);
    if (enq_ok) sb_commit_store(base7, 4'b1010, 32'h5566_7788);

    t7_exp = 32'h5522_7744;

    @(posedge clk);
    display_state("T7 before forwards");

    do_forward_check("T7_FULL", base7, 4'b1111, 1'b1, 1'b0, t7_exp);
    do_forward_check("T7_SUB1", base7, 4'b0101, 1'b1, 1'b0, t7_exp);
    do_forward_check("T7_SUB2", base7, 4'b1010, 1'b1, 1'b0, t7_exp);

    // Drain any remaining entries using snapshot of count
    num_to_drain = dut.count_q;
    for (k = 0; k < num_to_drain; k = k + 1) begin
      do_drain_one("T7_CLEANUP", 1'b1, drain_ok, addr_d, wmask_d, wdata_d);
    end

    // ---------------- Test 8: Random multi-address pattern with coalescing ----------------
    $display("\nTest 8: Random multi-address pattern with coalescing");
    clear_scoreboard();

    base8_a = 32'h0000_7000;
    base8_b = 32'h0000_7008;

    for (k = 0; k < 32; k = k + 1) begin
      seed  = seed + 32'h1357_9BDF;
      data8 = seed;

      mask8_a = 4'b0010;
      mask8_b = 4'b1000;

      if ((k % 2) == 0) begin
        do_enq_store($sformatf("T8_A%0d", k), base8_a, mask8_a, data8, 1'b1, enq_ok);
        if (enq_ok) sb_commit_store(base8_a, mask8_a, data8);
      end else begin
        do_enq_store($sformatf("T8_B%0d", k), base8_b, mask8_b, data8, 1'b1, enq_ok);
        if (enq_ok) sb_commit_store(base8_b, mask8_b, data8);
      end
    end

    @(posedge clk);
    display_state("T8 after enqueues");

    // Drain snapshot of current count
    num_to_drain = dut.count_q;
    for (k = 0; k < num_to_drain; k = k + 1) begin
      do_drain_one("T8_DRAIN", 1'b1, drain_ok, addr_d, wmask_d, wdata_d);
      if (drain_ok) sb_pcsb_store(addr_d, wmask_d, wdata_d);
    end

    sb_check_equal("T8");

    @(posedge clk);
    display_state("T8 after drains");

    $display("\nAll PCSB tests finished (no flush).\n");
    $finish;
  end

endmodule : pcsb_tb
