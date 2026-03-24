module ROB 
import rv32i_types::*;
#(
  // parameter integer XLEN        = 32,
  parameter integer LOG_REGS    = rv32i_types::NUM_ARCH_REG,
  parameter integer PHY_REGS    = rv32i_types::NUM_PHYS_REG,
  parameter integer ROB_ENTRIES = rv32i_types::NUM_ROB_ENTRIES,
  // parameter integer STORE_VALUE_IN_ROB = 0,

  localparam integer LOG_BITS = $clog2(LOG_REGS),
  localparam integer PRF_BITS = $clog2(PHY_REGS),
  localparam integer ROB_BITS = $clog2(ROB_ENTRIES)
)(
  input  logic clk,
  input  logic rst,

  // Rename -> ROB
  input dispatch_to_ROB_t rtrob,
  output ROB_to_dispatch_t  rob_to_dispatch,

  // CDB -> ROB
  input  cdb_entry_t        cdbrob_rob,

  // Commit <- ROB
  output ROB_to_RRF_t       rob_to_rrf,
  input RRF_to_ROB_t       rrf_to_rob, 

  // Control / Status
  output logic                 rob_full,
  output logic                 rob_empty,
  output logic [ROB_BITS:0]    rob_count,
  output logic [ROB_BITS-1:0]  rob_head_idx,
  output logic [ROB_BITS-1:0]  rob_tail_idx,
  output logic                 commit_valid,
  input  logic                        src_sample_we,         
  input  logic [ROB_BITS-1:0]         src_sample_idx,         
  input  logic [31:0]                 src_sample_rs1_val,    
  input  logic [31:0]                 src_sample_rs2_val,
  // input  logic                        br_update_valid,
  // input  logic [ROB_BITS-1:0]         br_update_idx,
  input  logic                        br_taken,
  input  logic [31:0]                 br_target,
  // input logic                        is_ctrl_logic,
  input logic                       flush_valid,
  output logic                 commit_branch_taken,
  output logic [31:0]          commit_branch_target,
  output logic        bpred_update_valid,
  output logic [7:0]  bpred_update_idx,
  output logic        bpred_update_taken
);

  localparam logic [ROB_BITS:0] ROB_ENTRIES_U = ROB_ENTRIES;
  localparam logic [ROB_BITS-1:0] LAST_IDX = ROB_ENTRIES-1;
  ROB_entry_t     rob_entries [ROB_ENTRIES];

  // Pointers / count
  logic [ROB_BITS-1:0]  head_q, head_d;
  logic [ROB_BITS-1:0]  tail_q, tail_d;
  logic [ROB_BITS:0]    cnt_q,  cnt_d;

  logic        bpred_update_valid_d;
  logic [7:0]  bpred_update_idx_d;
  logic        bpred_update_taken_d;

  // logic commit_valid;
  logic [31:0] inst_local, ea_local;
  logic [6:0]  opc;
  logic [2:0]  f3;
  logic rob_flush;
  logic head_is_branch;

  assign rob_flush = flush_valid;

  assign rob_head_idx = head_q;
  assign rob_tail_idx = tail_q;
  assign rob_count    = cnt_q;

  logic do_alloc, do_commit;

  // commit is allowed when head is ready and not empty
  // assign commit_valid = rrf_to_rob.dequeue && (rob_empty == 1'b0) && rob_entries[head_q].ready;
  logic rob_flush_q;
  always_ff @(posedge clk) begin
    if (rst) rob_flush_q <= 1'b0;
    else     rob_flush_q <= rob_flush;
  end
  logic commit_ready;
  logic commit_fire;
  assign commit_ready  = (!rob_empty) && rob_entries[head_q].ready;
  assign commit_valid  = commit_ready;
  assign commit_fire   = rrf_to_rob.dequeue && commit_ready;

  logic [63:0] rob_order_ctr_q;
  always_ff @(posedge clk) begin
    if (rst)         rob_order_ctr_q <= 64'd0;
    else if (do_alloc) rob_order_ctr_q <= rob_order_ctr_q + 64'd1;
  end

  // ---------- Combinational ----------
  always_comb begin
    // defaults
    head_d = head_q;
    tail_d = tail_q;
    cnt_d  = cnt_q;

    bpred_update_valid_d = 1'b0;
    bpred_update_idx_d   = '0;
    bpred_update_taken_d = 1'b0;

    rob_full  = (cnt_q == ROB_ENTRIES_U);
    rob_empty = (cnt_q == '0);

    // backpressure to Dispatch (OUTPUT, not rtrob)
    rob_to_dispatch.is_rob_full   = rob_full;
    rob_to_dispatch.rob_entry_idx = tail_q;

    // expose head entry to RRF (zero when empty)
    rob_to_rrf           = '0;
    rob_to_rrf.is_rob_empty = rob_empty;
    if (!rob_empty) rob_to_rrf.rob_entry = rob_entries[head_q];

    // local enables
    do_alloc  = rtrob.enqueue_rob && !rob_full;
    // do_commit = rrf_to_rob.dequeue && !rob.empty;
    do_commit = rrf_to_rob.dequeue && commit_ready;

    // pointer updates with wrap
    if (do_alloc)  tail_d = (tail_q == LAST_IDX) ? '0 : (tail_q + 1'b1);
    if (do_commit) head_d = (head_q == LAST_IDX) ? '0 : (head_q + 1'b1);

    // count
    cnt_d = cnt_q + (do_alloc ? 1'd1 : 1'd0) - (do_commit ? 1'd1 : 1'd0);

    head_is_branch = !rob_empty &&
                     (rob_entries[head_q].opcode == 7'b1100011   // BEQ/BNE/...
                      // || rob_entries[head_q].opcode == 7'b1100111 // JALR, if you want it too
                     );

    // “branch taken at commit” (static not-taken scheme)
    commit_branch_taken  = do_commit && br_taken;
    commit_branch_target = rob_entries[head_q].br_target;

    // When we actually commit a branch at the head, send predictor update
    if (do_commit && rob_entries[head_q].is_branch) begin
      bpred_update_valid_d = 1'b1;
      bpred_update_idx_d   = rob_entries[head_q].bht_idx;
      bpred_update_taken_d = rob_entries[head_q].br_taken;
    end

    bpred_update_valid = bpred_update_valid_d;
    bpred_update_idx   = bpred_update_idx_d;
    bpred_update_taken = bpred_update_taken_d;
  end

  // ---------- Sequential ----------
  integer i;
  always_ff @(posedge clk) begin
    if (rst) begin
      head_q <= '0;
      tail_q <= '0;
      cnt_q  <= '0;

      for (i = 0; i < ROB_ENTRIES; i++) rob_entries[i] <= '0;

    end else begin
      // only flush instructions younger than the branch on mispredict
      if(rob_flush) begin
        head_q <= '0;
        tail_q <= '0;
        cnt_q  <= '0;
      end else begin
        head_q <= head_d;
        tail_q <= tail_d;
        cnt_q  <= cnt_d;
      end

      // for (i = 0; i < ROB_ENTRIES; i++) begin
        if (rob_flush) rob_entries <= '{default: '0};
      // end

        // Allocate write into current tail_q
        if (do_alloc) begin
          rob_entries[tail_q].rd        <= rtrob.rd;
          rob_entries[tail_q].pd        <= rtrob.pd;
          rob_entries[tail_q].pd_old    <= rtrob.pd_old;   // <-- add
          rob_entries[tail_q].dest_we   <= rtrob.dest_we;
          rob_entries[tail_q].opcode    <= rtrob.opcode;
          rob_entries[tail_q].pc        <= rtrob.pc;
          rob_entries[tail_q].order     <= rob_order_ctr_q;

          rob_entries[tail_q].ready     <= 1'b0;
          rob_entries[tail_q].value     <= '0;            // clear until WB
          rob_entries[tail_q].exc       <= 1'b0;
          rob_entries[tail_q].exc_cause <= '0;            // no cause yet

          rob_entries[tail_q].mem_addr  <= '0;            // not a store yet
          rob_entries[tail_q].mem_wmask <= '0;
          rob_entries[tail_q].mem_wdata <= '0;

          rob_entries[tail_q].commit    <= 1'b0;          // optional tag
          rob_entries[tail_q].inst      <= rtrob.inst;    
          rob_entries[tail_q].rs1       <= rtrob.rs1;      
          rob_entries[tail_q].rs2       <= rtrob.rs2;     
          rob_entries[tail_q].uses_rs1  <= rtrob.uses_rs1; 
          rob_entries[tail_q].uses_rs2  <= rtrob.uses_rs2;

          rob_entries[tail_q].rs1_value   <= '0;
          rob_entries[tail_q].rs2_value   <= '0;

          rob_entries[tail_q].br_taken    <= '0;
          rob_entries[tail_q].br_target   <= '0;

          // NEW: predictor metadata + branch tag
          rob_entries[tail_q].is_branch  <= rtrob.is_branch;
          rob_entries[tail_q].bht_idx    <= rtrob.bht_idx;
          rob_entries[tail_q].pred_taken <= rtrob.pred_taken;
          rob_entries[tail_q].pred_target   <= rtrob.pred_target;
        end

        if (br_taken) begin
          rob_entries[head_q].br_taken  <= br_taken;
          rob_entries[head_q].br_target <= br_target;
        end

        if(src_sample_we) begin
          rob_entries[src_sample_idx].rs1_value <= src_sample_rs1_val;
          rob_entries[src_sample_idx].rs2_value <= src_sample_rs2_val;

          if (!rob_entries[src_sample_idx].dest_we) rob_entries[src_sample_idx].ready <= 1'b1;

          inst_local = rob_entries[src_sample_idx].inst;
          opc = rob_entries[src_sample_idx].opcode;
          f3 = inst_local[14:12];

          if ((opc == 7'b0000011) || (opc == 7'b0100011)) begin
            ea_local = src_sample_rs1_val + ((opc == 7'b0100011) ? {{20{inst_local[31]}}, inst_local[31:25], inst_local[11:7]} : {{21{inst_local[31]}}, inst_local[30:20]});
            rob_entries[src_sample_idx].mem_addr <= ea_local;
            if (opc == 7'b0100011) begin
              unique case (f3)
                3'b000: begin // sb
                  rob_entries[src_sample_idx].mem_wmask <= 4'b0001 << ea_local[1:0];
                  unique case (ea_local[1:0])
                    2'b00: rob_entries[src_sample_idx].mem_wdata <= {24'b0, src_sample_rs2_val[7:0]};
                    2'b01: rob_entries[src_sample_idx].mem_wdata <= {16'b0, src_sample_rs2_val[7:0], 8'b0};
                    2'b10: rob_entries[src_sample_idx].mem_wdata <= {8'b0, src_sample_rs2_val[7:0], 16'b0};
                    2'b11: rob_entries[src_sample_idx].mem_wdata <= {src_sample_rs2_val[7:0], 24'b0};
                  endcase
                end
                3'b001: begin // sh
                  rob_entries[src_sample_idx].mem_wmask <= ea_local[1] ? 4'b1100 : 4'b0011;
                  rob_entries[src_sample_idx].mem_wdata <= ea_local[1] ? {src_sample_rs2_val[15:0], 16'b0} : {16'b0, src_sample_rs2_val[15:0]};
                end
                3'b010: begin // sw
                  rob_entries[src_sample_idx].mem_wmask <= 4'b1111;
                  rob_entries[src_sample_idx].mem_wdata <= src_sample_rs2_val;
                end
                default: begin
                  rob_entries[src_sample_idx].mem_wmask <= 4'b0000;
                  rob_entries[src_sample_idx].mem_wdata <= 32'b0;
                end
              endcase
              rob_entries[src_sample_idx].value <= src_sample_rs2_val;
            end
          end
        end

        if (do_commit) begin
          rob_entries[head_q].commit <= 1'b1;
        end

        // Writeback (CDB)
        if (cdbrob_rob.valid) begin
          rob_entries[cdbrob_rob.rob_entry_idx].value <= cdbrob_rob.value;
          rob_entries[cdbrob_rob.rob_entry_idx].ready <= 1'b1;
          rob_entries[cdbrob_rob.rob_entry_idx].exc <= cdbrob_rob.exc;
        end
      end
  end

endmodule
