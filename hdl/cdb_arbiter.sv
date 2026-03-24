// cdb_arbiter.sv — 4-way round-robin (ALU, MUL, DIV) --> single CDB
module cdb_arbiter #(
  parameter integer XLEN = 32
)(
  input  logic clk,
  input  logic rst,

  // ALU
  input  logic            v0,
  output logic            r0,
  input  logic [XLEN-1:0] val0,
  input  logic [4:0]      rd0,
  input  logic [9:0]      pd0,
  input  logic [5:0]      rob0,
  input  logic            we0,

  // MUL
  input  logic            v1,
  output logic            r1,
  input  logic [XLEN-1:0] val1,
  input  logic [4:0]      rd1,
  input  logic [9:0]      pd1,
  input  logic [5:0]      rob1,
  input  logic            we1,

  // DIV
  input  logic            v2,
  output logic            r2,
  input  logic [XLEN-1:0] val2,
  input  logic [4:0]      rd2,
  input  logic [9:0]      pd2,
  input  logic [5:0]      rob2,
  input  logic            we2,

  // MEM
  input  logic            v3,
  output logic            r3,
  input  logic [XLEN-1:0] val3,
  input  logic [4:0]      rd3,
  input  logic [9:0]      pd3,
  input  logic [5:0]      rob3,
  input  logic            we3,

  // CDB out
  output logic            cdb_valid,
  input  logic            cdb_ready,
  output logic [XLEN-1:0] cdb_value,
  output logic [4:0]      cdb_rd,
  output logic [9:0]      cdb_pd,
  output logic [5:0]      cdb_rob,
  output logic            cdb_we,

  //new inputs for branch info from winning FU
  input  logic        is_ctrl0,
  input  logic        br_taken0,
  input  logic [31:0] br_target0,
  input  logic [6:0]  opcode0,
  input  logic [31:0] pc0,

  //New CDB Outputs
  output logic        cdb_is_ctrl,     // 1 for branch/jal/jalr from the winning FU
  output logic        cdb_br_taken,    // valid when cdb_is_ctrl && branch
  output logic [31:0] cdb_br_target,   // valid when cdb_is_ctrl
  output logic [6:0]  cdb_opcode,      // opcode of the winning instruction
  output logic [31:0] cdb_pc
);

  typedef enum logic [1:0] {S0,S1,S2,S3} rr_t;
  rr_t rr_q, rr_d, sel;

  logic picked;

  // Default
  always_comb begin
    cdb_valid = 1'b0;
    cdb_value = '0;
    cdb_rd    = '0;
    cdb_pd    = '0;
    cdb_rob   = '0;
    cdb_we    = 1'b0;
    picked = 1'b0;
    cdb_is_ctrl = 1'b0;
    cdb_br_taken = 1'b0;
    cdb_br_target = 32'b0;
    cdb_opcode = 7'b0;
    cdb_pc = 32'b0;

    r0 = 1'b0; r1 = 1'b0; r2 = 1'b0; r3 = 1'b0;
    rr_d = rr_q;

    // Round-robin pick first available starting at rr_q
    for (integer unsigned k = 0; k < 4; k++) begin
      sel = rr_t'((rr_q + k) % 4);
      if (!picked) begin
        unique case (sel)
          S0: if (v0) begin
                cdb_valid = 1'b1; cdb_value = val0; cdb_rd = rd0; cdb_pd = pd0; cdb_rob = rob0; cdb_we = we0;
                r0 = cdb_ready; picked = 1'b1; rr_d = S1; cdb_is_ctrl=is_ctrl0; cdb_br_taken=br_taken0; cdb_br_target=br_target0; cdb_opcode=opcode0; cdb_pc=pc0;
                r0=cdb_ready;
              end
          S1: if (v1) begin
                cdb_valid = 1'b1; cdb_value = val1; cdb_rd = rd1; cdb_pd = pd1; cdb_rob = rob1; cdb_we = we1;
                r1 = cdb_ready; picked = 1'b1; rr_d = S2;
              end
          S2: if (v2) begin
                cdb_valid = 1'b1; cdb_value = val2; cdb_rd = rd2; cdb_pd = pd2; cdb_rob = rob2; cdb_we = we2;
                r2 = cdb_ready; picked = 1'b1; rr_d = S3;
              end
          S3: if (v3) begin
                cdb_valid = 1'b1; cdb_value = val3; cdb_rd = rd3; cdb_pd = pd3; cdb_rob = rob3; cdb_we = we3;
                r3 = cdb_ready; picked = 1'b1; rr_d = S0;
              end

          default: ; 
        endcase
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst) rr_q <= S0;
    else if (cdb_valid && cdb_ready) rr_q <= rr_d;
  end
endmodule