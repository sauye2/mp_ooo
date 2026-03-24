module lsq
import rv32i_types::*;
#(
  parameter Q_ENTRIES = 16
)(
  input  logic clk,
  input  logic rst,
  input  logic enq_valid,
  output logic enq_ready,
  input  logic is_store,
  input  logic [31:0] base_addr,
  input  logic [31:0] offset,
  input  logic [31:0] store_data,
  input  logic [2:0] funct3,
  input  logic [$clog2(NUM_ROB_ENTRIES)-1:0] rob_idx,
  input  logic [PHYS_REG_IDX:0] pd,
  input  logic [ARCH_REG_IDX:0] rd,

  // D-cache interface (loads only - stores go through PCSB)
  output logic [31:0] dcache_addr,
  output logic [3:0]  dcache_rmask,
  output logic [3:0]  dcache_wmask,
  output logic [31:0] dcache_wdata,
  input  logic [31:0] dcache_rdata,
  input  logic        dcache_resp,

  output logic resp_valid,
  input  logic resp_ready,
  output logic [31:0] resp_value,
  output logic [ARCH_REG_IDX:0] resp_rd,
  output logic [PHYS_REG_IDX:0] resp_pd,
  output logic [$clog2(NUM_ROB_ENTRIES)-1:0] resp_rob_idx,
  output logic resp_dest_we,

  // Commit interface - stores dequeue immediately (PCSB takes ownership)
  // Note: addr/wmask/wdata are handled by cpu.sv -> PCSB, kept for interface compatibility
  input  logic commit_store_valid,
  input  logic [$clog2(NUM_ROB_ENTRIES)-1:0] commit_store_rob_idx,
  input  logic [31:0] commit_store_addr,
  input  logic [3:0] commit_store_wmask,
  input  logic [31:0] commit_store_wdata,
  output logic commit_store_ready,

  // PCSB forwarding interface
  output logic [31:0] pcsb_fwd_addr,
  output logic [3:0]  pcsb_fwd_rmask,
  input  logic        pcsb_fwd_full_hit,
  input  logic        pcsb_fwd_partial,
  input  logic [31:0] pcsb_fwd_data,

  input  logic flush,
  input  logic cand_has_older_store_unknown,
  output logic [$clog2(NUM_ROB_ENTRIES)-1:0] cand_rob_idx
);

  typedef logic [$clog2(Q_ENTRIES)-1:0] q_idx_t;
  typedef logic [$clog2(Q_ENTRIES):0]   q_cnt_t;

  lsq_entry_t q[Q_ENTRIES];
  q_cnt_t q_count;
  q_idx_t q_head, q_tail;

  logic port_busy_q, port_busy_d;
  logic [31:0] port_addr_q, port_addr_d;
  logic [3:0] port_rmask_q, port_rmask_d;

  logic ld_inflight_q, ld_inflight_d;
  q_idx_t ld_idx_q, ld_idx_d;

  logic [31:0] ea_calc;
  assign ea_calc = base_addr + offset;

  logic unused;
  assign unused = &{1'b0, commit_store_addr, commit_store_wmask, commit_store_wdata};

  wire q_has_space = (q_count != q_cnt_t'(Q_ENTRIES));
  assign enq_ready = q_has_space;

  logic cand_valid;
  q_idx_t cand_idx;
  always_comb begin
    cand_valid = 1'b0;
    cand_idx = q_head;
    if (q[q_head].valid && !q[q_head].is_store && !q[q_head].done) begin
      cand_valid = 1'b1;
      cand_idx = q_head;
    end
  end
  assign cand_rob_idx = cand_valid ? q[cand_idx].rob : '0;

  logic [3:0] cand_rmask;
  always_comb begin
    unique case (q[cand_idx].f3)
      3'b000, 3'b100: cand_rmask = 4'b0001 << q[cand_idx].a10;
      3'b001, 3'b101: cand_rmask = q[cand_idx].a10[1] ? 4'b1100 : 4'b0011;
      default:        cand_rmask = 4'b1111;
    endcase
  end
  assign pcsb_fwd_addr  = cand_valid ? q[cand_idx].word_addr : 32'h0;
  assign pcsb_fwd_rmask = cand_valid ? cand_rmask : 4'b0000;
  assign commit_store_ready = 1'b1;
  assign dcache_addr  = port_addr_q;
  assign dcache_rmask = port_busy_q ? port_rmask_q : 4'b0000;
  assign dcache_wmask = 4'b0000;
  assign dcache_wdata = 32'h0;

  logic [3:0] rm;
  always_comb begin
    port_busy_d = port_busy_q;
    port_addr_d = port_addr_q;
    port_rmask_d = port_rmask_q;
    ld_inflight_d = ld_inflight_q;
    ld_idx_d = ld_idx_q;

    if (!port_busy_q && !resp_valid && cand_valid && !cand_has_older_store_unknown) begin
      if (pcsb_fwd_full_hit) begin
      end else if (pcsb_fwd_partial) begin
      end else begin
        unique case (q[cand_idx].f3)
          3'b000, 3'b100: rm = 4'b0001 << q[cand_idx].a10;
          3'b001, 3'b101: rm = q[cand_idx].a10[1] ? 4'b1100 : 4'b0011;
          default:        rm = 4'b1111;
        endcase
        port_busy_d = 1'b1;
        port_addr_d = q[cand_idx].word_addr;
        port_rmask_d = rm;
        ld_inflight_d = 1'b1;
        ld_idx_d = cand_idx;
      end
    end
  end

  integer k;
  logic [31:0] wword;
  logic [3:0] wmask;
  logic [31:0] val;
  logic [31:0] rd_word;
  logic do_enq, do_load_deq, do_store_deq;
  logic do_pcsb_fwd;
  always_ff @(posedge clk) begin
    if (rst || flush) begin
      for (k = 0; k < Q_ENTRIES; k++) begin
        q[k] <= '0;
      end
      q_count <= '0;
      q_head <= '0;
      q_tail <= '0;
      port_busy_q <= 1'b0;
      port_addr_q <= '0;
      port_rmask_q <= '0;
      ld_inflight_q <= 1'b0;
      ld_idx_q <= '0;
      resp_valid <= 1'b0;
      resp_value <= '0;
      resp_rd <= '0;
      resp_pd <= '0;
      resp_rob_idx <= '0;
      resp_dest_we <= 1'b0;

    end else begin
      port_busy_q <= port_busy_d;
      port_addr_q <= port_addr_d;
      port_rmask_q <= port_rmask_d;
      ld_inflight_q <= ld_inflight_d;
      ld_idx_q <= ld_idx_d;
      resp_valid <= (resp_valid && !resp_ready) ? 1'b1 : 1'b0;
      do_enq = enq_valid && enq_ready;
      do_load_deq = resp_valid && resp_ready && q[q_head].valid && !q[q_head].is_store && q[q_head].done;
      do_store_deq = commit_store_valid && q[q_head].valid && q[q_head].is_store && (q[q_head].rob == commit_store_rob_idx);         // stores deq immediately when commit happens and pcsb takes them
      do_pcsb_fwd = !port_busy_q && !resp_valid && cand_valid && !cand_has_older_store_unknown && pcsb_fwd_full_hit;
      q_count <= q_count + (do_enq ? q_cnt_t'(1) : q_cnt_t'(0)) - ((do_load_deq || do_store_deq) ? q_cnt_t'(1) : q_cnt_t'(0));

      if (do_enq) begin
        q[q_tail].valid <= 1'b1;
        q[q_tail].done <= 1'b0;
        q[q_tail].ea <= ea_calc;
        q[q_tail].word_addr <= {ea_calc[31:2], 2'b00};
        q[q_tail].a10 <= ea_calc[1:0];
        q[q_tail].f3 <= funct3;
        q[q_tail].rob <= rob_idx;
        q[q_tail].pd_s <= pd;
        q[q_tail].rd_s <= rd;
        q[q_tail].value <= 32'h0;
        q[q_tail].wword <= 32'h0;
        q[q_tail].wmask <= 4'h0;
        if (is_store) begin
          wword = 32'h0;
          wmask = 4'h0;
          unique case (funct3)
            3'b000: begin
              wmask = 4'b0001 << ea_calc[1:0];
              unique case (ea_calc[1:0])
                2'd0: wword = {24'h0, store_data[7:0]};
                2'd1: wword = {16'h0, store_data[7:0], 8'h0};
                2'd2: wword = {8'h0, store_data[7:0], 16'h0};
                default: wword = {store_data[7:0], 24'h0};
              endcase
            end
            3'b001: begin
              wmask = ea_calc[1] ? 4'b1100 : 4'b0011;
              wword = ea_calc[1] ? {store_data[15:0], 16'h0} : {16'h0, store_data[15:0]};
            end
            default: begin
              wmask = 4'b1111;
              wword = store_data;
            end
          endcase
          q[q_tail].is_store <= 1'b1;
          q[q_tail].wword <= wword;
          q[q_tail].wmask <= wmask;
        end else begin
          q[q_tail].is_store <= 1'b0;
        end
        q_tail <= q_idx_t'((q_tail + 1'b1) % Q_ENTRIES);
      end
      if (do_pcsb_fwd) begin
        rd_word = pcsb_fwd_data;
        val = 32'h0;
        unique case(q[cand_idx].f3)
          3'b000: begin
            unique case (q[cand_idx].a10)
              2'd0: val = {{24{rd_word[7]}}, rd_word[7:0]};
              2'd1: val = {{24{rd_word[15]}}, rd_word[15:8]};
              2'd2: val = {{24{rd_word[23]}}, rd_word[23:16]};
              default: val = {{24{rd_word[31]}}, rd_word[31:24]};
            endcase
          end
          3'b100: begin
            unique case (q[cand_idx].a10)
              2'd0: val = {24'h0, rd_word[7:0]};
              2'd1: val = {24'h0, rd_word[15:8]};
              2'd2: val = {24'h0, rd_word[23:16]};
              default: val = {24'h0, rd_word[31:24]};
            endcase
          end
          3'b001: begin
            val = q[cand_idx].a10[1] ? {{16{rd_word[31]}}, rd_word[31:16]} : {{16{rd_word[15]}}, rd_word[15:0]};
          end
          3'b101: begin
            val = q[cand_idx].a10[1] ? {16'h0, rd_word[31:16]} : {16'h0, rd_word[15:0]};
          end
          default: begin
            val = rd_word;
          end
        endcase
        q[cand_idx].value <= val;
        q[cand_idx].done <= 1'b1;
        resp_valid <= 1'b1;
        resp_value <= val;
        resp_rd <= q[cand_idx].rd_s;
        resp_pd <= q[cand_idx].pd_s;
        resp_rob_idx <= q[cand_idx].rob;
        resp_dest_we <= 1'b1;
      end

      if (dcache_resp && port_busy_q && ld_inflight_q) begin
        rd_word = dcache_rdata;
        val = 32'h0;
        unique case(q[ld_idx_q].f3)
          3'b000: begin
            unique case (q[ld_idx_q].a10)
              2'd0: val = {{24{rd_word[7]}}, rd_word[7:0]};
              2'd1: val = {{24{rd_word[15]}}, rd_word[15:8]};
              2'd2: val = {{24{rd_word[23]}}, rd_word[23:16]};
              default: val = {{24{rd_word[31]}}, rd_word[31:24]};
            endcase
          end
          3'b100: begin
            unique case (q[ld_idx_q].a10)
              2'd0: val = {24'h0, rd_word[7:0]};
              2'd1: val = {24'h0, rd_word[15:8]};
              2'd2: val = {24'h0, rd_word[23:16]};
              default: val = {24'h0, rd_word[31:24]};
            endcase
          end
          3'b001: begin
            val = q[ld_idx_q].a10[1] ? {{16{rd_word[31]}}, rd_word[31:16]} : {{16{rd_word[15]}}, rd_word[15:0]};
          end
          3'b101: begin
            val = q[ld_idx_q].a10[1] ? {16'h0, rd_word[31:16]} : {16'h0, rd_word[15:0]};
          end
          default: begin
            val = rd_word;
          end
        endcase
        q[ld_idx_q].value <= val;
        q[ld_idx_q].done <= 1'b1;
        resp_valid <= 1'b1;
        resp_value <= val;
        resp_rd <= q[ld_idx_q].rd_s;
        resp_pd <= q[ld_idx_q].pd_s;
        resp_rob_idx <= q[ld_idx_q].rob;
        resp_dest_we <= 1'b1;
        ld_inflight_q <= 1'b0;
        port_busy_q <= 1'b0;
      end

      if (do_load_deq) begin
        q[q_head] <= '0;
        q_head <= q_idx_t'((q_head + 1'b1) % Q_ENTRIES);
      end

      if (do_store_deq) begin
        q[q_head] <= '0;
        q_head <= q_idx_t'((q_head + 1'b1) % Q_ENTRIES);
      end
    end
  end

endmodule : lsq