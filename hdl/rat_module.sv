// RAT.sv  (ERR-style, no commit ports; Ready bt lives in RAT row)
// Columns conceptually: [Ready | Logical(row) | Physical(mapped PRF)]
// Logical reg index == row index (x0..x31). We never rename x0.
//Will add the branching logic in CP3!!!
module RAT
import rv32i_types::*;
#(
  // Put sizes first; derive widths afterwards so $clog2 works in every tool.
  parameter integer LOG_REGS  = rv32i_types::NUM_ARCH_REG,                 // number of logical integer regs
  parameter integer PHY_REGS  = rv32i_types::NUM_PHYS_REG,                // number of physical regs
  localparam integer LOG_BITS  = $clog2(LOG_REGS),
  localparam integer PRF_BITS  = $clog2(PHY_REGS)
)(
  input  logic                 clk,
  input  logic                 rst,

  // Rename-to-RAT from Dispatch/Rename
  input ren_to_rat_req_t       rat_req, // rs1, rs2, rd, rd_alloc, pd_new
  output rat_to_ren_rsp_t      rat_rsp, // ps1, ps2, pd_new, ps1_valid, ps2_valid, pd_valid

  // CDB-to-RAT (cdb_*) — from Common Data Bus
  input cdb_entry_t        cdb_entry, // rd, pd, valid, rob_entry_idx, ...
  input logic              flush_valid,
  input logic [PRF_BITS-1:0] rrat_map [0:LOG_REGS-1]

);

  // Storage: one row per logical reg: current PRF mapping + Ready bt
  logic [PRF_BITS-1:0] rat_map   [0:LOG_REGS-1]; // logical -> physical
  logic               rat_ready [0:LOG_REGS-1];  // readiness of CURRENT mapping

  // -----------------------------------------
  // Combinational reads for rename sources
  // -----------------------------------------

  assign rat_rsp.ps1        = rat_map  [rat_req.rs1];
  assign rat_rsp.ps2        = rat_map  [rat_req.rs2];
  assign rat_rsp.ps1_valid  = rat_ready[rat_req.rs1];
  assign rat_rsp.ps2_valid  = rat_ready[rat_req.rs2];

  // new mapping for the dest (read-before-write same cycle)
  assign rat_rsp.pd_new     = rat_req.pd_new;
  assign rat_rsp.pd_valid = rat_req.rd_alloc && rat_req.alloc_ok && (rat_req.rd != '0);
  assign rat_rsp.rd_old_pd = (rat_req.rd == '0) ? '0 : rat_map[rat_req.rd];

  // Sequential updates
  //   - Reset: identity map; x0 hardwired to p0 and always ready
  //   - CDB snoop: mark row(s) ready if their mapped PRF == cdb_prf
  //   - Rename write: update mapping for ldest; clear Ready (new value not ready)
  integer unsigned i;
  always_ff @(posedge clk) begin
    if (rst) begin
      for (i = 0; i < LOG_REGS; i++) begin
        if (i < PHY_REGS) begin
          rat_map[i]   <= PRF_BITS'(i); // identity mapping on reset
          rat_ready[i] <= 1'b1;         // start ready; will clear on first rename
        end else begin
          rat_map[i]   <= '0;
          rat_ready[i] <= 1'b0;
        end
      end
      // x0 is special (hardwired zero): never renamed, always ready
      rat_map[0]   <= '0;   // assume p0 is the zero PRF
      rat_ready[0] <= 1'b1;
    end else if (flush_valid) begin
      for (i = 0; i < LOG_REGS; i++) begin
        rat_map[i] <= rrat_map[i];
        rat_ready[i] <= 1'b1;
      end
      rat_map[0]  <= '0;   // assume p0 is the zero PRF
      rat_ready[0] <= 1'b1;

      // if (cdb_entry.valid && cdb_entry.rd != '0) begin
      //   rat_map[cdb_entry.rd] <= cdb_entry.pd;
      //   rat_ready[cdb_entry.rd] <= 1'b1;
      // end
    end else begin
      // 1) CDB snoop — mark ready if the row currently points to cdb_prf
      if (cdb_entry.valid) begin
        for (i = 0; i < LOG_REGS; i++) begin
          if (rat_map[i] == cdb_entry.pd)
            rat_ready[i] <= 1'b1;
        end
      end

      // 2) Speculative rename write — update mapping and clear Ready
      if (rat_req.rd_alloc && rat_req.alloc_ok) begin
        if (rat_req.rd != '0) begin  // never rename x0
          rat_map  [rat_req.rd] <= rat_req.pd_new;
          rat_ready[rat_req.rd] <= 1'b0;
        end
      end
    end
  end

endmodule
