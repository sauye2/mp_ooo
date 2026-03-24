module alu 
import rv32i_types::*; #(
  parameter integer XLEN = 32
)(
  input  logic clk,
  input  logic rst,

  // From RS
  input  logic                                        req_valid,
  output logic                                        req_ready,
  input  logic [XLEN-1:0]                             op_a,
  input  logic [XLEN-1:0]                             op_b,
  input  logic [XLEN-1:0]                             op_imm,
  input  logic [3:0]                                   alu_op,
  input  logic [rv32i_types::ARCH_REG_IDX:0]          rd_arch,
  input  logic [rv32i_types::PHYS_REG_IDX:0]          pd_phys,
  input  logic [$clog2(rv32i_types::NUM_ROB_ENTRIES)-1:0] rob_idx,
  input  logic                                        dest_we,

  input  logic [31:0]                                 pc,
  input  logic [6:0]                                  opcode,
  input  logic [2:0]                                  funct3,
  // To CDB
  output logic                                        resp_valid,
  input  logic                                        resp_ready,
  output logic [XLEN-1:0]                             resp_value,
  output logic [rv32i_types::ARCH_REG_IDX:0]          resp_rd,
  output logic [rv32i_types::PHYS_REG_IDX:0]          resp_pd,
  output logic [$clog2(rv32i_types::NUM_ROB_ENTRIES)-1:0] resp_rob_idx,
  output logic                                        resp_dest_we,
  output logic                                        br_taken,
  output logic [31:0]                                 br_target,
  output logic                                        is_ctrl_inst,
  output logic                                       is_branch_mod,
  output logic                                       is_jalr_mod
);
  assign req_ready = resp_ready || !resp_valid;

  logic [XLEN-1:0] res;

  logic is_branch, is_jal, is_jalr, br_cond;
  logic        br_taken_q, br_taken_d;
  logic [31:0] br_target_q, br_target_d;
  logic        is_ctrl_q, is_ctrl_d;

  always_comb begin
    is_branch = (opcode == 7'b1100011);          // br
    is_jal    = (opcode == 7'b1101111);          // jal
    is_jalr   = (opcode == 7'b1100111);          // jalr
    is_ctrl_d = is_branch || is_jal || is_jalr;
  end

  always_comb begin
    br_cond = 1'b0;
    if (is_branch) begin
      unique case (funct3)
        3'b000: br_cond = (op_a == op_b);                    // beq
        3'b001: br_cond = (op_a != op_b);                    // bne
        3'b100: br_cond = ($signed(op_a) < $signed(op_b));   // blt
        3'b101: br_cond = ($signed(op_a) >= $signed(op_b));  // bge
        3'b110: br_cond = (op_a < op_b);                     // bltu
        3'b111: br_cond = (op_a >= op_b);                    // bgeu
        default: br_cond = 1'b0;
      endcase
    end
  end

  always_comb begin
    br_taken_d = 1'b0;
    br_target_d = pc + 32'd4;
    
    if (is_branch) begin
      br_taken_d = br_cond;
      br_target_d = br_cond ? (pc + op_imm) : (pc + 32'd4);
    end else if (is_jal) begin
      br_taken_d = 1'b1;
      br_target_d = pc + op_imm;
    end else if (is_jalr) begin
      br_taken_d = 1'b1;
      br_target_d = (op_a + op_imm) & 32'hFFFFFFFE;      // clear lsb
    end
  end

always_comb begin
  unique case (alu_op)
    4'h0: res = op_a + op_b;                          // ADD
    4'h1: res = op_a - op_b;                          // SUB
    4'h2: res = op_a ^ op_b;                          // XOR
    4'h3: res = op_a | op_b;                          // OR
    4'h4: res = op_a & op_b;                          // AND
    4'h5: res = op_a << op_b[4:0];                    // SLL

    // SRA: do arithmetic shift in signed domain, then cast result
    4'h6: res = $unsigned($signed(op_a) >>> op_b[4:0]);

    4'h7: res = op_a >> ((op_imm != 32'b0) ? op_imm[4:0] : op_b[4:0]); // SRL/SRLI
    4'h8: res = {31'b0, $signed(op_a) < $signed((op_imm != 32'b0) ? op_imm : op_b)}; // SLT/SLTI
    4'h9: res = {31'b0, op_a < ((op_imm != 32'b0) ? op_imm : op_b)};                 // SLTU/SLTIU
    4'hA: res = op_a + op_imm;                        // ADDI
    4'hB: res = op_a ^ op_imm;                        // XORI
    4'hC: res = op_a | op_imm;                        // ORI
    4'hD: res = op_a & op_imm;                        // ANDI
    4'hE: res = op_a << op_imm[4:0];                  // SLLI

    // SRAI: same idea
    4'hF: res = $unsigned($signed(op_a) >>> op_imm[4:0]);

    default: res = '0;
  endcase

  if (is_jal || is_jalr) begin
    res = pc + 32'd4;  // Save return address
  end
end


  always_ff @(posedge clk) begin
    if (rst) begin
      resp_valid   <= 1'b0;
      resp_value   <= '0;
      resp_rd      <= '0;
      resp_pd      <= '0;
      resp_rob_idx <= '0;
      resp_dest_we <= 1'b0;
      br_taken_q <= 1'b0;
      br_target_q <= '0;
      is_ctrl_q <= 1'b0;
      is_branch_mod <= 1'b0;
      is_jalr_mod <= 1'b0;
    end else begin
      if (req_valid && req_ready) begin
        resp_valid   <= 1'b1;
        resp_value   <= res;
        resp_rd      <= rd_arch;
        resp_pd      <= pd_phys;
        resp_rob_idx <= rob_idx;
        resp_dest_we <= dest_we;
        br_taken_q <= br_taken_d;
        br_target_q <= br_target_d;
        is_ctrl_q <= is_ctrl_d;
        is_branch_mod <= is_branch;
        is_jalr_mod <= is_jalr;
      end else if (resp_valid && resp_ready) begin
        resp_valid <= 1'b0;
        br_taken_q <= 1'b0;
        is_ctrl_q <= 1'b0;
        is_branch_mod <= 1'b0;
        is_jalr_mod <= 1'b0;
      end
    end
  end

  assign br_taken = br_taken_q;
  assign br_target = br_target_q;
  assign is_ctrl_inst = is_ctrl_q;

endmodule
