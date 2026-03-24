module div
  import rv32i_types::*;
#(
  parameter XLEN = 32
)(
  input  logic clk,
  input  logic rst,

  input  logic        req_valid,
  output logic        req_ready,
  input  logic [XLEN-1:0] op_a,
  input  logic [XLEN-1:0] op_b,
  input  logic [ARCH_REG_IDX:0] rd_arch,
  input  logic [PHYS_REG_IDX:0] pd_phys,
  input  logic [$clog2(NUM_ROB_ENTRIES)-1:0] rob_idx,
  input  logic        dest_we,
  input  logic [2:0]    sub_op,

  output logic        resp_valid,
  input  logic        resp_ready,
  output logic [XLEN-1:0] resp_value,
  output logic [ARCH_REG_IDX:0] resp_rd,
  output logic [PHYS_REG_IDX:0] resp_pd,
  output logic [$clog2(NUM_ROB_ENTRIES)-1:0] resp_rob_idx,
  output logic        resp_dest_we
);

  localparam integer STAGES = 2;

  // logic [XLEN-1:0] quotient, remainder;
  // logic divide_by_zero;
  logic [XLEN-1:0] q_s, r_s;  logic div0_s;
  logic [XLEN-1:0] q_u, r_u;  logic div0_u;
  logic [2:0]       subop_pipe_q[STAGES], subop_pipe_d[STAGES];
  logic [XLEN-1:0]  a_pipe_q   [STAGES], a_pipe_d   [STAGES];
  logic             a_intmin_q [STAGES], a_intmin_d [STAGES];
  logic             b_neg1_q   [STAGES], b_neg1_d   [STAGES];
  logic             sign_a_pipe_q[STAGES], sign_a_pipe_d[STAGES];
  logic             sign_b_pipe_q[STAGES], sign_b_pipe_d[STAGES];


  logic [STAGES-1:0] valid_pipe_q, valid_pipe_d;
  logic [ARCH_REG_IDX:0] rd_pipe_q[STAGES], rd_pipe_d[STAGES];
  logic [PHYS_REG_IDX:0] pd_pipe_q[STAGES], pd_pipe_d[STAGES];
  logic [$clog2(NUM_ROB_ENTRIES)-1:0] rob_pipe_q[STAGES], rob_pipe_d[STAGES];
  logic we_pipe_q[STAGES], we_pipe_d[STAGES];
  logic buf_value_q, buf_value_d;
  logic [XLEN-1:0] buf_val_q, buf_val_d;
  logic [ARCH_REG_IDX:0] buf_rd_q, buf_rd_d;
  logic [PHYS_REG_IDX:0] buf_pd_q, buf_pd_d;
  logic [$clog2(NUM_ROB_ENTRIES)-1:0] buf_rob_q, buf_rob_d;
  logic buf_we_q, buf_we_d;
  

  logic [XLEN-1:0] a_q, a_d;
  logic [XLEN-1:0] b_q, b_d;
  
  wire pipe_out_v = valid_pipe_q[STAGES-1];
  wire stall_out = pipe_out_v && buf_value_q && !resp_ready;
  wire adv_pipe = (|valid_pipe_q || (req_valid && !stall_out)) && !stall_out;
  wire req_fire = req_valid && !stall_out;
  wire signed_op = (sub_op == 3'b100) || (sub_op == 3'b110);

  always_comb begin
    a_d = a_q;
    b_d = b_q;
    if (req_fire) begin
      if (signed_op) begin
        a_d = op_a[XLEN-1] ? -op_a : op_a;
        b_d = op_b[XLEN-1] ? -op_b : op_b;
      end else begin
        a_d = op_a;
        b_d = op_b;
      end
    end
  end

  DW_div_pipe #(
    .a_width     (XLEN),
    .b_width     (XLEN),
    .tc_mode     (0),   
    .rem_mode    (1),
    .num_stages  (STAGES),
    .stall_mode  (1),
    .rst_mode    (1),
    .op_iso_mode (0)
  ) U_div (
    .clk        (clk),
    .rst_n      (~rst),
    .en         (adv_pipe),
    .a          (a_q),
    .b          (b_q),
    .quotient   (q_u),
    .remainder  (r_u),
    .divide_by_0(div0_u)
  );



  always_comb begin
    valid_pipe_d = valid_pipe_q;
    for (integer i = 0; i < STAGES; i++) begin
      rd_pipe_d[i] = rd_pipe_q[i];
      pd_pipe_d[i] = pd_pipe_q[i];
      rob_pipe_d[i] = rob_pipe_q[i];
      we_pipe_d[i] = we_pipe_q[i];
      subop_pipe_d[i] = subop_pipe_q[i];
      a_pipe_d[i] = a_pipe_q[i];
      a_intmin_d[i] = a_intmin_q[i];
      b_neg1_d[i] = b_neg1_q[i];
      sign_a_pipe_d[i] = sign_a_pipe_q[i];
      sign_b_pipe_d[i] = sign_b_pipe_q[i];
    end
    if (adv_pipe) begin
      for (integer i = STAGES-1; i > 0; i--) begin
        rd_pipe_d[i] = rd_pipe_q[i-1];
        pd_pipe_d[i] = pd_pipe_q[i-1];
        rob_pipe_d[i] = rob_pipe_q[i-1];
        we_pipe_d[i] = we_pipe_q[i-1];
        subop_pipe_d[i] = subop_pipe_q[i-1];
        a_pipe_d[i] = a_pipe_q[i-1];
        a_intmin_d[i] = a_intmin_q[i-1];
        b_neg1_d[i] = b_neg1_q[i-1];
        sign_a_pipe_d[i] = sign_a_pipe_q[i-1];
        sign_b_pipe_d[i] = sign_b_pipe_q[i-1];
      end
      if (req_fire) begin
        rd_pipe_d[0] = rd_arch;
        pd_pipe_d[0] = pd_phys;
        rob_pipe_d[0] = rob_idx;
        we_pipe_d[0] = dest_we;
        subop_pipe_d[0] = sub_op;
        a_pipe_d[0] = op_a;
        a_intmin_d[0] = (op_a == 32'h80000000);
        b_neg1_d[0] = (op_b == 32'hFFFFFFFF);
        sign_a_pipe_d[0] = op_a[XLEN-1];
        sign_b_pipe_d[0] = op_b[XLEN-1];
      end
      valid_pipe_d = {valid_pipe_q[STAGES-2:0], req_fire};
    end
  end

  wire pop = buf_value_q && resp_ready;
  wire push = pipe_out_v && (!buf_value_q || resp_ready);

  // logic [XLEN-1:0] sel_val;
  logic            is_div0_s, is_div0_u, ovf_s;
  assign is_div0_s = div0_s;
  assign is_div0_u = div0_u;
  assign ovf_s     = a_intmin_q[STAGES-1] & b_neg1_q[STAGES-1]; 

  always_comb begin
    div0_s = div0_u;
    q_s = q_u;
    r_s = r_u;
    if (!div0_u && !ovf_s) begin
      if (sign_a_pipe_q[STAGES-1] ^ sign_b_pipe_q[STAGES-1]) begin
        q_s = -q_u;
      end
      if (sign_a_pipe_q[STAGES-1]) begin
        r_s = -r_u;
      end
    end
  end

  always_comb begin
    buf_value_d = (buf_value_q & ~pop) | push;
    buf_val_d = buf_val_q;
    buf_rd_d = buf_rd_q;
    buf_pd_d = buf_pd_q;
    buf_rob_d = buf_rob_q;
    buf_we_d = buf_we_q;

    if (push) begin
      // buf_val_d = divide_by_zero ? '1 : quotient;
      unique case(subop_pipe_q[STAGES-1])
      3'b100: begin // DIV
        buf_val_d = is_div0_s ? 32'hFFFF_FFFF : (ovf_s ? 32'h8000_0000 : q_s);
      end
      3'b101: begin // DIVU
        buf_val_d = is_div0_u ? {XLEN{1'b1}} : q_u;
      end
      3'b110: begin // REM
        buf_val_d = is_div0_s ? a_pipe_q[STAGES-1] : (ovf_s ? '0 : r_s);
      end
      3'b111: begin // REMU
        buf_val_d = is_div0_u ? a_pipe_q[STAGES-1] : r_u;
      end 
      default: ; // do nothing
      endcase
      buf_rd_d = rd_pipe_q[STAGES-1];
      buf_pd_d = pd_pipe_q[STAGES-1];
      buf_rob_d = rob_pipe_q[STAGES-1];
      buf_we_d = we_pipe_q[STAGES-1];
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      valid_pipe_q <= '0;
      for (integer i = 0; i < STAGES; i++) begin
        rd_pipe_q[i] <= '0;
        pd_pipe_q[i] <= '0;
        rob_pipe_q[i] <= '0;
        we_pipe_q[i] <= 1'b0;
        subop_pipe_q[i] <= '0;
        a_pipe_q[i] <= '0;
        a_intmin_q[i] <= 1'b0;
        b_neg1_q[i] <= 1'b0;
        sign_a_pipe_q[i] <= 1'b0;
        sign_b_pipe_q[i] <= 1'b0;
      end
      buf_value_q <= 1'b0;
      buf_val_q <= '0;
      buf_rd_q <= '0;
      buf_pd_q <= '0;
      buf_rob_q <= '0;
      buf_we_q <= 1'b0;
      a_q <= '0;
      b_q <= '0;
    end else begin
      valid_pipe_q <= valid_pipe_d;
      for (integer i = 0; i < STAGES; i++) begin
        rd_pipe_q[i] <= rd_pipe_d[i];
        pd_pipe_q[i] <= pd_pipe_d[i];
        rob_pipe_q[i] <= rob_pipe_d[i];
        we_pipe_q[i] <= we_pipe_d[i];
        subop_pipe_q[i] <= subop_pipe_d[i];
        a_pipe_q[i] <= a_pipe_d[i];
        a_intmin_q[i] <= a_intmin_d[i];
        b_neg1_q[i] <= b_neg1_d[i];
        sign_a_pipe_q[i] <= sign_a_pipe_d[i];
        sign_b_pipe_q[i] <= sign_b_pipe_d[i];
      end
      buf_value_q <= buf_value_d;
      buf_val_q <= buf_val_d;
      buf_rd_q <= buf_rd_d;
      buf_pd_q <= buf_pd_d;
      buf_rob_q <= buf_rob_d;
      buf_we_q <= buf_we_d;
      a_q <= a_d;
      b_q <= b_d;
    end
  end
 
  assign resp_valid   = buf_value_q;
  assign req_ready    = !stall_out;
  assign resp_value   = buf_val_q;
  assign resp_rd      = buf_rd_q;
  assign resp_pd      = buf_pd_q;
  assign resp_rob_idx = buf_rob_q;
  assign resp_dest_we = buf_we_q;

endmodule
