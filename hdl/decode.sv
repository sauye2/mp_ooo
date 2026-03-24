module decode
import rv32i_types::*;
(
    input  logic        clk,
    input  logic        rst,
    input  logic        iq_valid,      // inst queue has a head entry
    input  logic [31:0] iq_pc,         // pc from queue head
    input  logic [31:0] iq_inst,       // inst from queue head
    output logic        iq_ready,      // decode can accept inst and dequeue
    // To dispatch
    output logic                  dec_valid,
    input  logic                  dec_ready,
    output logic [ARCH_REG_IDX:0] dec_rs1,
    output logic [ARCH_REG_IDX:0] dec_rs2,
    output logic [ARCH_REG_IDX:0] dec_rd,
    output logic [31:0]           dec_imm,
    output logic [3:0]            dec_alu_op,
    output logic [6:0]            dec_opcode,
    output logic                  dec_dest_we,
    output logic [1:0]            dec_fukind,   // 0:ALU 1:MUL 2:DIV  3:unused
    output logic [31:0]           dec_pc,
    output logic [63:0]           dec_order,
    output logic [31:0]           dec_inst,
    output logic [2:0]            dec_subop,
    input logic                   dec_flush,
    input logic [7:0]         iq_bht_idx,
    input logic              iq_pred_taken,
    input logic [31:0]         iq_pred_target,
     // NEW: prediction meta to dispatch
    output logic                  dec_pred_taken,
    output logic [7:0]            dec_bht_idx,
    output logic [31:0]           dec_pred_target
);
    logic valid_q, valid_d;
    logic [31:0] pc_q, pc_d;
    logic [31:0] inst_q, inst_d;
    logic [7:0] bht_idx_q, bht_idx_d;
    logic pred_taken_q, pred_taken_d;
    logic [31:0] pred_target_q, pred_target_d;
    logic [2:0] subop;
    assign iq_ready = !valid_q || (valid_q && dec_ready);
    assign dec_inst = inst_q;

    always_ff @(posedge clk) begin
        if (rst||dec_flush) begin
            valid_q <= 1'b0;
            pc_q <= '0;
            inst_q <= '0;
            pred_taken_q <= 1'b0;
            bht_idx_q <= '0;
            pred_target_q <= '0;
        end else begin
            valid_q <= valid_d;
            pc_q <= pc_d;
            inst_q <= inst_d;
            pred_taken_q <= pred_taken_d;
            bht_idx_q <= bht_idx_d;
            pred_target_q <= pred_target_d;
        end
    end

    always_comb begin
        valid_d = valid_q;
        pc_d = pc_q;
        inst_d = inst_q;
        pred_taken_d = pred_taken_q;
        bht_idx_d    = bht_idx_q;
        pred_target_d = pred_target_q;
        if (valid_q && dec_ready) begin
            valid_d = 1'b0;
        end
        if (iq_valid && iq_ready) begin
            valid_d = 1'b1;
            pc_d = iq_pc;
            inst_d = iq_inst;
            pred_taken_d = iq_pred_taken;
            bht_idx_d    = iq_bht_idx;
            pred_target_d = iq_pred_target;
        end
    end

    logic [63:0] order_q;
    always_ff @(posedge clk) begin
        if (rst) begin
            order_q <= 64'd0;
        end else if (dec_valid && dec_ready) begin
            order_q <= order_q + 64'd1;
        end
    end
    assign dec_order = order_q;

    logic [6:0] opcode;
    logic [4:0] rd, rs1, rs2;
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic [31:0] i_imm, u_imm, s_imm, b_imm, j_imm;
    assign funct3 = inst_q[14:12];
    assign funct7 = inst_q[31:25];
    assign opcode = inst_q[6:0];
    assign rs1    = inst_q[19:15];
    assign rs2    = inst_q[24:20];
    assign rd     = inst_q[11:7];
    assign i_imm  = {{21{inst_q[31]}}, inst_q[30:20]};
    assign u_imm  = {inst_q[31:12], 12'b0};
    assign s_imm  = {{20{inst_q[31]}}, inst_q[31:25], inst_q[11:7]};
    assign b_imm  = {{20{inst_q[31]}}, inst_q[7], inst_q[30:25], inst_q[11:8], 1'b0};
    assign j_imm  = {{11{inst_q[31]}}, inst_q[19:12], inst_q[20], inst_q[30:21], 1'b0};

    logic [3:0] aluop;
    logic [1:0] fuk;
    logic [31:0] imm_sel;
    logic [ARCH_REG_IDX:0] rs1_o, rs2_o;
    logic dest_we;

    always_comb begin
        rs1_o = rs1;
        rs2_o = rs2;
        dest_we = 1'b0;
        aluop = 4'h0;
        fuk = 2'd0;    
        imm_sel  = 32'd0;
        subop = 3'd0;
        unique case (opcode)
        op_b_reg: begin           // r-type
            dest_we = (rd != '0);
            if (funct7 == 7'b0000001) begin
            unique case (funct3)
                3'b000: begin fuk = 2'd1; aluop = 4'h0; end // MUL
                3'b001: begin fuk = 2'd1; aluop = 4'h1; end // MULH (signed*signed, take hi)
                3'b010: begin fuk = 2'd1; aluop = 4'h2; end // MULHSU (signed*unsigned, hi)
                3'b011: begin fuk = 2'd1; aluop = 4'h3; end // MULHU (unsigned*unsigned, hi)
                3'b100: begin fuk = 2'd2; aluop = 4'h4; end // DIV
                3'b101: begin fuk = 2'd2; aluop = 4'h5; end // DIVU
                3'b110: begin fuk = 2'd2; aluop = 4'h6; end // REM
                3'b111: begin fuk = 2'd2; aluop = 4'h7; end // REMU
            endcase
            subop = funct3;
            // aluop = 4'h0;
            end else begin
            fuk = 2'd0;      // alu
            unique case (funct3)
                3'b000: aluop = (funct7[5] ? 4'h1 : 4'h0);    // SUB : ADD
                3'b100: aluop = 4'h2;                         // XOR
                3'b110: aluop = 4'h3;                         // OR
                3'b111: aluop = 4'h4;                         // AND
                3'b001: aluop = 4'h5;                         // SLL
                3'b101: aluop = (funct7[5] ? 4'h6 : 4'h7);    // SRA : SRL
                3'b010: aluop = 4'h8;                         // SLT
                3'b011: aluop = 4'h9;                         // SLTU
                default: ;
            endcase
            end
        end
        op_b_imm: begin               // i-type
            dest_we = (rd != '0);
            fuk = 2'd0;       // alu
            imm_sel = i_imm;
            rs2_o = '0;
            unique case (funct3)
            3'b000: aluop = 4'hA;      // ADDI
            3'b100: aluop = 4'hB;     // XORI
            3'b110: aluop = 4'hC;     // ORI
            3'b111: aluop = 4'hD;     // ANDI
            3'b001: begin             // SLLI
                aluop = 4'hE;
            end
            3'b101: begin
                if (inst_q[30]) begin
                    aluop = 4'hF;   // SRAI
                end
                else begin 
                    aluop = 4'h7;   // SRLI
                end
            end
            3'b010: aluop = 4'h8;    // SLTI
            3'b011: aluop = 4'h9;    // SLTIU
            default: fuk = 2'd0;
            endcase
        end

        op_b_lui: begin
            dest_we = (rd != '0);
            fuk     = 2'd0;        // alu
            rs1_o   = '0;
            rs2_o   = '0;
            imm_sel = u_imm;
            aluop   = 4'hA;        // ADDI
        end

        op_b_auipc: begin
            dest_we = (rd != '0);
            imm_sel = pc_q + u_imm;
            fuk     = 2'd0;        // alu
            rs1_o   = '0;
            rs2_o   = '0;
            aluop   = 4'hA;        // ADDI
        end

        op_b_br: begin
            dest_we = 1'b0;
            imm_sel = b_imm;
            fuk = 2'd0;
            aluop = 4'h0;
        end

        op_b_load: begin
            dest_we = (rd != '0);
            imm_sel = i_imm;
            fuk = 2'd3;              // lsu
            aluop = 4'hA;
            rs2_o = '0;
        end

        op_b_store: begin
            dest_we = 1'b0;
            imm_sel = s_imm;
            fuk = 2'd3;              // lsu
            aluop = 4'hA;
        end

        op_b_jal: begin
            dest_we = (rd != '0);
            imm_sel = j_imm;
            rs1_o = '0;
            rs2_o = '0;
            fuk = 2'd0;
            aluop = 4'h0;
        end

        op_b_jalr: begin
            dest_we = (rd != '0);
            imm_sel = i_imm;
            fuk = 2'd0;
            aluop = 4'h0;
            rs1_o = rs1;
            rs2_o = '0;
        end

        default: ;
        endcase
    end

    assign dec_pc = pc_q;
    assign dec_rs1 = rs1_o;
    assign dec_rs2 = rs2_o;
    assign dec_rd = rd;
    assign dec_imm = imm_sel;
    assign dec_alu_op = aluop;
    assign dec_fukind = fuk;
    assign dec_dest_we = dest_we;
    assign dec_valid = valid_q;
    assign dec_opcode = opcode;
    assign dec_subop = subop;
    // NEW: prediction meta to dispatch
    assign dec_pred_taken = pred_taken_q;
    assign dec_bht_idx = bht_idx_q;
    assign dec_pred_target = pred_target_q;
endmodule : decode
