// ====================================================================
// dispatch.sv — ERR Dispatch connecting RAT, ROB, and per-FU RSes
// - Reads logical src/dst from decoder
// - Queries RAT for physicals and readiness
// - Allocates ROB slot (tail) and new PD (from freelist via RAT.req)
// - Enqueues uop into the selected Reservation Station
// - Backpressures when ROB full, RS full, or alloc not OK
// ====================================================================

module dispatch 
import rv32i_types::*; #(
  parameter integer XLEN = 32
)(
  // ---------------- Decode inputs ----------------
  input  logic                                dec_valid,
  output logic                                dec_ready,
  input  logic [rv32i_types::ARCH_REG_IDX:0]  dec_rs1,
  input  logic [rv32i_types::ARCH_REG_IDX:0]  dec_rs2,
  input  logic [rv32i_types::ARCH_REG_IDX:0]  dec_rd,
  input  logic [XLEN-1:0]                     dec_imm,
  input  logic [3:0]                          dec_alu_op,
  input  logic [6:0]                          dec_opcode,
  input  logic                                dec_dest_we,    // uop writes rd?
  input  logic [1:0]                          dec_fukind,     // 0:ALU 1:MUL 2:DIV
  input  logic [31:0]                         dec_pc,
  input  logic [63:0]                         dec_order,
  input  logic [31:0]                         dec_inst,
  input logic [2:0]                          dec_subop,
  output logic [2:0]                         mult_subop,
  output logic [2:0]                         div_subop,
  output logic [2:0]                         mem_subop,

  // ---------------- Freelist (external) ----------------
  input  logic                                fl_alloc_gnt,    // 1 if a PD is available
  input  logic [rv32i_types::PHYS_REG_IDX:0]  fl_pd_alloc,      // new PD for rd

  // ---------------- RAT ----------------
  output rv32i_types::ren_to_rat_req_t        rat_req,
  input  rv32i_types::rat_to_ren_rsp_t        rat_rsp,

  // ---------------- ROB ----------------
  output rv32i_types::dispatch_to_ROB_t       rtrob,          // allocate when we fire
  input  rv32i_types::ROB_to_dispatch_t       rob2dis,        // {rob_entry_idx,is_rob_full}

  // ---------------- RS: ALU ----------------
  output logic                                alu_enq_valid,
  input  logic                                alu_enq_ready,
  output logic [rv32i_types::PHYS_REG_IDX:0]  alu_ps1,
  output logic [rv32i_types::PHYS_REG_IDX:0]  alu_ps2,
  output logic                                alu_rs1_rdy,
  output logic                                alu_rs2_rdy,
  output logic [XLEN-1:0]                     alu_imm,
  output logic [3:0]                          alu_op,
  output logic [rv32i_types::PHYS_REG_IDX:0]  alu_pd,
  output logic [rv32i_types::ARCH_REG_IDX:0]  alu_rd,
  output logic [$clog2(rv32i_types::NUM_ROB_ENTRIES)-1:0] alu_rob_idx,
  output logic                                alu_dest_we,
  output logic [31:0]                         alu_pc,
  output logic [6:0]                          alu_opcode,
  output logic [2:0]                          alu_funct3,
  // output logic [31:0]                         mem_pc,           // for later when we start mem
  // output logic [6:0]                          mem_opcode,
  // output logic [2:0]                          mem_funct3,

  // ---------------- RS: MUL ----------------
  output logic                                mul_enq_valid,
  input  logic                                mul_enq_ready,
  output logic [rv32i_types::PHYS_REG_IDX:0]  mul_ps1,
  output logic [rv32i_types::PHYS_REG_IDX:0]  mul_ps2,
  output logic                                mul_rs1_rdy,
  output logic                                mul_rs2_rdy,
  output logic [rv32i_types::PHYS_REG_IDX:0]  mul_pd,
  output logic [rv32i_types::ARCH_REG_IDX:0]  mul_rd,
  output logic [$clog2(rv32i_types::NUM_ROB_ENTRIES)-1:0] mul_rob_idx,
  output logic                                mul_dest_we,

  // ---------------- RS: DIV ----------------
  output logic                                div_enq_valid,
  input  logic                                div_enq_ready,
  output logic [rv32i_types::PHYS_REG_IDX:0]  div_ps1,
  output logic [rv32i_types::PHYS_REG_IDX:0]  div_ps2,
  output logic                                div_rs1_rdy,
  output logic                                div_rs2_rdy,
  output logic [rv32i_types::PHYS_REG_IDX:0]  div_pd,
  output logic [rv32i_types::ARCH_REG_IDX:0]  div_rd,
  output logic [$clog2(rv32i_types::NUM_ROB_ENTRIES)-1:0] div_rob_idx,
  output logic                                div_dest_we,

  output logic                                mem_enq_valid,
  input  logic                                mem_enq_ready,
  output logic [rv32i_types::PHYS_REG_IDX:0]  mem_ps1,
  output logic [rv32i_types::PHYS_REG_IDX:0]  mem_ps2,
  output logic                                mem_rs1_rdy,
  output logic                                mem_rs2_rdy,
  output logic [XLEN-1:0]                     mem_imm,
  output logic [rv32i_types::PHYS_REG_IDX:0]  mem_pd,
  output logic [rv32i_types::ARCH_REG_IDX:0]  mem_rd,
  output logic [$clog2(rv32i_types::NUM_ROB_ENTRIES)-1:0]  mem_rob_idx,
  output logic                                mem_dest_we,
  output logic [2:0]                          mem_funct3,
  output logic [31:0]                         mem_pc,
  output logic [6:0]                          mem_opcode,
  // input logic                                redirect_valid,
  // input logic [31:0]                         redirect_pc,
  input  logic                                dec_pred_taken,
  input  logic [7:0]                          dec_bht_idx,
  input logic [31:0]                        dec_pred_target
);

  function automatic logic [1:0] decode_uses (input logic [6:0] opcode);
    unique case (opcode)
      7'b0110011: decode_uses = 2'b11; // R-type
      7'b0010011: decode_uses = 2'b10; // I-ALU
      7'b0000011: decode_uses = 2'b10; // LOAD
      7'b0100011: decode_uses = 2'b11; // STORE
      7'b1100011: decode_uses = 2'b11; // BRANCH
      7'b1100111: decode_uses = 2'b10; // JALR
      7'b1101111, 7'b0110111, 7'b0010111: decode_uses = 2'b00; // JAL/LUI/AUIPC
      default:    decode_uses = 2'b00;
    endcase
  endfunction



  // ---------------- Rename (RAT) request ----------------
  // x0 never renamed; force rd_alloc=0 when rd==0 or dec_dest_we==0
  logic will_write;
  assign will_write          = dec_dest_we && (dec_rd != '0);
  logic rs_can_accept;
  logic can_fire;
  logic uses_rs1, uses_rs2;
  assign can_fire = dec_valid && !rob2dis.is_rob_full && rs_can_accept && (!will_write || (rat_rsp.pd_valid && fl_alloc_gnt));

  assign rat_req.rs1         = dec_rs1;
  assign rat_req.rs2         = dec_rs2;
  assign rat_req.rd          = dec_rd;
  assign rat_req.rd_alloc    = will_write;
  assign rat_req.commit      = will_write && can_fire; // update RAT mapping at commit
  assign rat_req.pd_new      = (will_write && can_fire) ? fl_pd_alloc : '0;
  assign rat_req.alloc_ok    = fl_alloc_gnt;

  // ---------------- Resource checks ----------------
  // pick the target RS and its ready signal
  always_comb begin
    unique case (dec_fukind)
      2'd0: rs_can_accept = alu_enq_ready;
      2'd1: rs_can_accept = mul_enq_ready;
      2'd2: rs_can_accept = div_enq_ready;
      2'd3: rs_can_accept = mem_enq_ready;
      default: rs_can_accept = 1'b0;
    endcase
  end

  // we can dispatch if:
  //  - decode has a valid uop
  //  - target RS has space
  //  - ROB not full
  //  - if writing a dest: freelist ok and RAT will accept pd_new

  wire[1:0] uses;
  assign uses = decode_uses(dec_opcode);
  assign dec_ready = can_fire; // 1 uop per cycle

  // ---------------- Drive ROB allocate packet ----------------
  // NOTE: include pd_old if you want precise freeing on commit (ERR)
  assign rtrob.enqueue_rob = can_fire;
  assign rtrob.rd          = will_write ? dec_rd : 5'd0;
  assign rtrob.pd          = will_write ? rat_rsp.pd_new : '0;
  assign rtrob.pd_old      = will_write ? rat_rsp.rd_old_pd: '0;
  assign rtrob.dest_we     = will_write;
  assign rtrob.pc          = dec_pc;
  assign rtrob.order       = dec_order;
  assign rtrob.opcode      = dec_opcode;
  assign rtrob.inst        = dec_inst;
  assign rtrob.rs1         = dec_rs1[4:0];
  assign rtrob.rs2         = dec_rs2[4:0];
  assign rtrob.uses_rs1    = uses[1];
  assign rtrob.uses_rs2    = uses[0];
  // assign rtrob.br_taken    = redirect_valid;
  // assign rtrob.br_target   = redirect_pc;
  assign rtrob.pred_taken  = dec_pred_taken;
  assign rtrob.bht_idx     = dec_bht_idx;
  assign rtrob.is_branch   = (dec_opcode == 7'b1100011);
  assign rtrob.pred_target  = dec_pred_target;

  // ---------------- Drive RS enqueues ----------------
  // Common fields
  wire [$clog2(rv32i_types::NUM_ROB_ENTRIES)-1:0] rob_idx = rob2dis.rob_entry_idx;
  // Default deassert
  always_comb begin
    // ALU
    alu_enq_valid = 1'b0;  alu_ps1 = '0; alu_ps2 = '0; alu_rs1_rdy = 1'b0; alu_rs2_rdy = 1'b0;
    alu_imm = '0; alu_op = '0; alu_pd = '0; alu_rd = '0; alu_rob_idx = '0; alu_dest_we = 1'b0; 
    // MUL
    mul_enq_valid = 1'b0;  mul_ps1 = '0; mul_ps2 = '0; mul_rs1_rdy = 1'b0; mul_rs2_rdy = 1'b0;
    mul_pd = '0; mul_rd = '0; mul_rob_idx = '0; mul_dest_we = 1'b0; mult_subop = '0;
    // DIV
    div_enq_valid = 1'b0;  div_ps1 = '0; div_ps2 = '0; div_rs1_rdy = 1'b0; div_rs2_rdy = 1'b0;
    div_pd = '0; div_rd = '0; div_rob_idx = '0; div_dest_we = 1'b0; div_subop = '0;
    // MEM
    mem_enq_valid = 1'b0;  mem_ps1 = '0; mem_ps2 = '0; mem_rs1_rdy = 1'b0; mem_rs2_rdy = 1'b0;
    mem_pd = '0; mem_rd = '0; mem_rob_idx = '0; mem_dest_we = 1'b0; mem_subop = '0;

    mem_imm = '0; 
    mem_funct3 = '0; 
    mem_pc = '0; 
    mem_opcode = '0;
    alu_pc = '0;
    alu_opcode = '0;
    alu_funct3 = '0;

    if (can_fire) begin
      unique case (dec_fukind)
        2'd0: begin // ALU/IMM
          alu_enq_valid = 1'b1;
          alu_ps1       = rat_rsp.ps1;
          alu_ps2       = rat_rsp.ps2;
          alu_rs1_rdy   = rat_rsp.ps1_valid;
          alu_rs2_rdy   = rat_rsp.ps2_valid;
          alu_imm       = dec_imm;
          alu_op        = dec_alu_op;
          alu_pd        = rat_rsp.pd_new;
          alu_rd        = dec_rd;
          alu_rob_idx   = rob_idx;
          alu_dest_we   = will_write;
          alu_pc        = dec_pc;
          alu_opcode    = dec_opcode;
          alu_funct3    = dec_inst[14:12];
        end
        2'd1: begin // MUL
          mul_enq_valid = 1'b1;
          mul_ps1       = rat_rsp.ps1;
          mul_ps2       = rat_rsp.ps2;
          mul_rs1_rdy   = rat_rsp.ps1_valid;
          mul_rs2_rdy   = rat_rsp.ps2_valid;
          mul_pd        = rat_rsp.pd_new;
          mul_rd        = dec_rd;
          mul_rob_idx   = rob_idx;
          mul_dest_we   = will_write;
          mult_subop    = dec_subop;
        end
        2'd2: begin // DIV/REM
          div_enq_valid = 1'b1;
          div_ps1       = rat_rsp.ps1;
          div_ps2       = rat_rsp.ps2;
          div_rs1_rdy   = rat_rsp.ps1_valid;
          div_rs2_rdy   = rat_rsp.ps2_valid;
          div_pd        = rat_rsp.pd_new;
          div_rd        = dec_rd;
          div_rob_idx   = rob_idx;
          div_dest_we   = will_write;
          div_subop     = dec_subop;
        end
        2'd3: begin                             // for later when we start mem 
          mem_enq_valid = 1'b1;
          mem_ps1       = rat_rsp.ps1;
          mem_ps2       = rat_rsp.ps2;
          mem_rs1_rdy   = rat_rsp.ps1_valid;
          mem_rs2_rdy   = rat_rsp.ps2_valid;
          mem_pd        = rat_rsp.pd_new;
          mem_rd        = dec_rd;
          mem_rob_idx   = rob_idx;
          mem_dest_we   = will_write;
          mem_imm       = dec_imm;
          mem_funct3    = dec_inst[14:12];
          mem_pc        = dec_pc;
          mem_opcode    = dec_opcode;
        end
        default: ;
      endcase
    end
  end
endmodule