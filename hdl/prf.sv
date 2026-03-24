module prf 
import rv32i_types::*; #(
  parameter integer XLEN = 32
)(
  input  logic clk,
  input  logic rst,

  // 2R1W + CDB snoop
  input  logic [rv32i_types::PHYS_REG_IDX:0]  rs1_pid,
  input  logic [rv32i_types::PHYS_REG_IDX:0]  rs2_pid,
  output logic [XLEN-1:0]                      rs1_rdata,
  output logic [XLEN-1:0]                      rs2_rdata,
  output logic                                 rs1_ready,
  output logic                                 rs2_ready,

  // mark newly allocated pd not-ready
  input  logic                                 alloc_valid,
  input  logic [rv32i_types::PHYS_REG_IDX:0]   alloc_pid,

  // free list handled elsewhere (optional scrub here)
  input  logic                                 free_valid,
  input  logic [rv32i_types::PHYS_REG_IDX:0]   free_pid,

  // CDB writeback
  input  logic                                 cdb_valid,
  input  logic [rv32i_types::PHYS_REG_IDX:0]   cdb_pid,
  input  logic [XLEN-1:0]                      cdb_value
);
  localparam integer NUMP = rv32i_types::NUM_PHYS_REG;

  logic [XLEN-1:0] rf    [NUMP];
  logic            ready [NUMP];

  // comb read with CDB bypass
  always_comb begin
    rs1_rdata = rf[rs1_pid];
    rs2_rdata = rf[rs2_pid];

    rs1_ready = ready[rs1_pid] | (cdb_valid && (cdb_pid == rs1_pid));
    rs2_ready = ready[rs2_pid] | (cdb_valid && (cdb_pid == rs2_pid));

    if (cdb_valid && (cdb_pid == rs1_pid)) rs1_rdata = cdb_value;
    if (cdb_valid && (cdb_pid == rs2_pid)) rs2_rdata = cdb_value;
  end

  integer i;
  always_ff @(posedge clk) begin
    if (rst) begin
      for (i = 0; i < NUMP; i++) begin
        rf[i]    <= '0;
        ready[i] <= 1'b0;
      end
      rf[0]    <= '0; // x0
      ready[0] <= 1'b1;
    end else begin
      if (cdb_valid) begin
        rf[cdb_pid]    <= cdb_value;
        ready[cdb_pid] <= 1'b1;
      end
      if (alloc_valid) begin
        ready[alloc_pid] <= 1'b0;
      end
      if (free_valid) begin
        rf[free_pid] <= rf[free_pid];
      end
    end
  end
endmodule