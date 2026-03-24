module store_guard #(
  parameter NUM_ROB_ENTRIES = 64
)(
  input  logic clk,
  input  logic rst,
  input  logic flush,

  input  logic [$clog2(NUM_ROB_ENTRIES)-1:0] rob_head_idx,

  input  logic alloc_store_valid,
  input  logic [$clog2(NUM_ROB_ENTRIES)-1:0] alloc_store_rob_idx,

  input  logic commit_store_valid,
  input  logic [$clog2(NUM_ROB_ENTRIES)-1:0] commit_store_rob_idx,

  input  logic [$clog2(NUM_ROB_ENTRIES)-1:0] cand_rob_idx,
  output logic                               cand_has_older_store_unknown
);

  localparam ROBW = $clog2(NUM_ROB_ENTRIES);
  typedef logic [ROBW-1:0] rob_idx_t;
  typedef logic [ROBW:0]   rob_age_t;

  localparam rob_age_t N_EXT = rob_age_t'(NUM_ROB_ENTRIES);

  logic [NUM_ROB_ENTRIES-1:0] pending_q, pending_d;

  function automatic rob_age_t unwrap(input rob_idx_t x, input rob_idx_t head);
    rob_age_t x_ext, head_ext;
    begin
      x_ext    = rob_age_t'(x);
      head_ext = rob_age_t'(head);
      if (x >= head) unwrap = x_ext - head_ext;
      else           unwrap = x_ext + N_EXT - head_ext;
    end
  endfunction

  rob_age_t age_cand;
  rob_idx_t j_idx;
  rob_age_t age_j;

  always_comb begin
    pending_d = pending_q;
    if (alloc_store_valid)
      pending_d[alloc_store_rob_idx] = 1'b1;

    if (commit_store_valid)
      pending_d[commit_store_rob_idx] = 1'b0;
  end

  always_comb begin
    cand_has_older_store_unknown = 1'b0;
    age_cand = unwrap(rob_idx_t'(cand_rob_idx), rob_idx_t'(rob_head_idx));
    for (integer j = 0; j < NUM_ROB_ENTRIES; j++) begin 
      if (pending_q[j]) begin
        j_idx = rob_idx_t'(j);
        age_j = unwrap(j_idx, rob_idx_t'(rob_head_idx));
        if (age_j < age_cand)
          cand_has_older_store_unknown = 1'b1;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst || flush)
      pending_q <= '0;
    else
      pending_q <= pending_d;
  end

endmodule
