module pcsb
import rv32i_types::*;
#(
  parameter integer unsigned ENTRIES = 8
)(
  input  logic        clk,
  input  logic        rst,
  // input  logic        flush,       // unused for post-commit buffer
  // enqueue from commit
  input  logic        enq_valid,
  output logic        enq_ready,
  input  logic [31:0] enq_addr,
  input  logic [3:0]  enq_wmask,
  input  logic [31:0] enq_wdata,
  // drain to D-cache
  output logic [31:0] drain_addr,
  output logic [3:0]  drain_wmask,
  output logic [31:0] drain_wdata,
  output logic        drain_valid,
  input  logic        drain_ready,
  input  logic        drain_resp,
  // forwarding to LSU
  input  logic [31:0] fwd_addr,
  input  logic [3:0]  fwd_rmask,
  output logic        fwd_full_hit,
  output logic        fwd_partial,
  output logic [31:0] fwd_data,
  // status
  output logic        buf_empty,
  output logic        buf_full
);

  localparam integer unsigned IDX_W = $clog2(ENTRIES);

  pcsb_entry_t entries_q [ENTRIES];
  pcsb_entry_t entries_d [ENTRIES];

  // count can go 0..ENTRIES inclusive
  logic [IDX_W:0]     count_q, count_d;
  logic [IDX_W-1:0]   head_q,  head_d;
  logic [IDX_W-1:0]   tail_q,  tail_d;
  logic               drain_pending_q, drain_pending_d;
  logic [31:0]        enq_addr_aligned;
  logic               coalesce_hit;
  logic [IDX_W-1:0]   coalesce_idx;

  logic can_coalesce;

always_comb begin
  can_coalesce = 1'b0;
  if (enq_valid) begin
    for (integer unsigned i = 0; i < ENTRIES; i++) begin
      if (entries_q[i].valid &&
          (entries_q[i].addr[31:2] == enq_addr[31:2])) begin
        can_coalesce = 1'b1;
      end
    end
  end
end

  // status
  assign buf_empty = (count_q == '0);
  assign buf_full  = (count_q == (IDX_W+1)'(ENTRIES));

  // enqueue is allowed only if not full
  assign enq_ready = !buf_full || (buf_full && can_coalesce);

  // -----------------------
  // Forwarding logic
  // -----------------------
  logic [3:0]  fwd_mask_accum;
  logic [31:0] fwd_data_accum;
  
  
  logic drain_fire;

  always_comb begin
    fwd_mask_accum = 4'b0000;
    fwd_data_accum = 32'h0;

    for (integer unsigned i = 0; i < ENTRIES; i++) begin
      // Only look at valid queue entries
      if ((IDX_W+1)'(i) < count_q) begin
        logic [IDX_W-1:0] idx_local;
        logic [IDX_W:0]   sum;

        // head_q + i, wrap implicitly by slicing
        sum       = (IDX_W+1)'(head_q) + (IDX_W+1)'(i);     
        idx_local = IDX_W'(i);                

        if (entries_q[idx_local].valid &&
            (entries_q[idx_local].addr[31:2] == fwd_addr[31:2])) begin
          for (integer b = 0; b < 4; b++) begin
            if (entries_q[idx_local].wmask[b]) begin
              fwd_mask_accum[b]        = 1'b1;
              fwd_data_accum[b*8 +: 8] = entries_q[idx_local].wdata[b*8 +: 8];
            end
          end
        end
      end
    end
  end

  assign fwd_full_hit =
    (fwd_rmask != 4'b0) &&
    ((fwd_rmask & fwd_mask_accum) == fwd_rmask);

  assign fwd_partial =
    (fwd_rmask != 4'b0) &&
    ((fwd_rmask & fwd_mask_accum) != 4'b0) &&
    ((fwd_rmask & fwd_mask_accum) != fwd_rmask);

  assign fwd_data = fwd_data_accum;

  // -----------------------
  // Drain interface
  // -----------------------
  assign drain_valid = !buf_empty && !drain_pending_q;
  assign drain_addr  = entries_q[head_q].addr;
  assign drain_wmask = entries_q[head_q].wmask;
  assign drain_wdata = entries_q[head_q].wdata;

  // -----------------------
  // Main control
  // -----------------------
  always_comb begin
    // defaults
    for (integer unsigned i = 0; i < ENTRIES; i++) begin
      entries_d[i] = entries_q[i];
    end
    count_d         = count_q;
    head_d          = head_q;
    tail_d          = tail_q;
    drain_pending_d = drain_pending_q;
    enq_addr_aligned = {enq_addr[31:2], 2'b00};
    coalesce_hit     = 1'b0;
    coalesce_idx     = '0;

    // issue new drain request
    drain_fire = drain_valid && drain_ready;
    if (drain_fire) begin
      drain_pending_d = 1'b1;
    end

    // complete drain and pop head
    if (drain_resp && (drain_pending_q || drain_fire)) begin
      entries_d[head_q].valid = 1'b0;
      head_d                  = IDX_W'((head_q + 1) % ENTRIES);
      count_d                 = count_d - (IDX_W+1)'(1);
      drain_pending_d         = 1'b0;
    end

    // enqueue new store with coalescing
    if (enq_valid && enq_ready) begin
      for (integer unsigned j = 0; j < ENTRIES; j++) begin
        logic [IDX_W-1:0] idx_local;
        idx_local = IDX_W'(j);
        if (entries_d[idx_local].valid &&
            (entries_d[idx_local].addr == enq_addr_aligned) &&
            !((drain_pending_q || drain_fire) && (idx_local == head_q))) begin
          coalesce_hit = 1'b1;
          coalesce_idx = idx_local;
        end
      end
      if (coalesce_hit) begin
        logic [3:0] merged_mask;
        logic [31:0] merged_data;
        merged_mask = entries_d[coalesce_idx].wmask | enq_wmask;
        merged_data = entries_d[coalesce_idx].wdata;
        for (integer b = 0; b < 4; b++) begin
          if (enq_wmask[b]) begin
            merged_data[b*8 +: 8] = enq_wdata[b*8 +: 8];
          end
        end
        entries_d[coalesce_idx].wmask = merged_mask;
        entries_d[coalesce_idx].wdata = merged_data;
      end else begin
        entries_d[tail_q].valid = 1'b1;
        entries_d[tail_q].addr  = enq_addr_aligned;
        entries_d[tail_q].wmask = enq_wmask;
        entries_d[tail_q].wdata = enq_wdata;
        tail_d                  = IDX_W'((tail_q + 1) % ENTRIES);
        count_d                 = count_d + (IDX_W+1)'(1);
      end
    end
  end

  // -----------------------
  // State registers
  // -----------------------
  integer unsigned k;
  always_ff @(posedge clk) begin
    if (rst) begin
      for (k = 0; k < ENTRIES; k++) begin
        entries_q[k] <= '0;
      end
      count_q         <= '0;
      head_q          <= '0;
      tail_q          <= '0;
      drain_pending_q <= 1'b0;
    end else begin
      for (k = 0; k < ENTRIES; k++) begin
        entries_q[k] <= entries_d[k];
      end
      count_q         <= count_d;
      head_q          <= head_d;
      tail_q          <= tail_d;
      drain_pending_q <= drain_pending_d;
    end
  end

endmodule : pcsb
