module RRAT 
import rv32i_types::*;
#(
  parameter integer LOG_REGS = rv32i_types::NUM_ARCH_REG,
  parameter integer PHY_REGS = rv32i_types::NUM_PHYS_REG,
  localparam integer LOG_BITS = $clog2(LOG_REGS),
  localparam integer PRF_BITS = $clog2(PHY_REGS)
) (
  input  logic           clk,
  input  logic           rst,

  // ---- Commit interface (from ROB/commit stage) ----
  input  logic           commit_valid,   // 1 when we are retiring one head uop
  input  ROB_entry_t     commit_uop,     // head ROB row (must include .old_pd)

  // ---- Recovery / snapshot ----
//   input  logic           restore_req,    // pulse to request RAT := RRAT copy
  output logic [PHYS_REG_IDX:0] rrat_table [LOG_REGS], // exposed snapshot

  // ---- Freelist return of committed-old phys ----
  output logic                  free_valid,
  output logic [PHYS_REG_IDX:0] free_pd,
  // ---- Branch-taken at commit (static not-taken) ----
  output logic                  commit_branch_taken,
  output logic [31:0]           commit_branch_target
);

logic [PHYS_REG_IDX:0] table_q [LOG_REGS];
logic [PHYS_REG_IDX:0] table_d [LOG_REGS];
logic is_branch;

// ---------- Combinational ----------
always_comb begin

  free_valid = 1'b0;
  free_pd    = '0;
  // default values 
  for (integer i = 0; i < LOG_REGS; i++) begin
    table_d[i] = table_q[i];
  end
  // Commit update
  // if (commit_valid) begin
  //   table_d[commit_uop.rd] = commit_uop.pd;
  // end

  if (commit_valid && commit_uop.dest_we && (commit_uop.rd != '0)) begin
    free_valid     = 1'b1;
    free_pd        = commit_uop.pd_old;
    table_d[commit_uop.rd] = commit_uop.pd;
  end

  for (integer i = 0; i < LOG_REGS; i++) begin
      rrat_table[i] = table_q[i];
  end

  table_d[0] = '0; // x0 always maps to p0

  is_branch = (commit_uop.opcode == op_b_br) || (commit_uop.opcode == op_b_jalr);

  commit_branch_taken  = commit_valid && is_branch && commit_uop.br_taken;
  commit_branch_target = commit_uop.br_target;

end

// ---------- Sequential ----------
always_ff @(posedge clk) begin
  if (rst) begin
    // Boot map: x0 -> p0, x1..x(LOG_REGS-1) -> p1..p(LOG_REGS-1)
    table_q[0] <= '0;          // x0 pinned to phys 0
    for (integer i = 1; i < LOG_REGS; i++) begin
      table_q[i] <= pd_t'(i);   // identity; width auto-resizes
    end
  end else begin
    for (integer i = 1; i < LOG_REGS; i++) begin
      table_q[i] <= table_d[i];
    end
    table_q[0] <= '0;
  end
end

endmodule
