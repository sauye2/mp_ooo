module mul
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
  input   logic [2:0]    sub_op,

  output logic        resp_valid,
  input  logic        resp_ready,
  output logic [XLEN-1:0] resp_value,
  output logic [ARCH_REG_IDX:0] resp_rd,
  output logic [PHYS_REG_IDX:0] resp_pd,
  output logic [$clog2(NUM_ROB_ENTRIES)-1:0] resp_rob_idx,
  output logic        resp_dest_we
);

  localparam integer STAGES = 2;

  logic [63:0] prod_ss;
  logic [63:0] prod_uu;
  logic [XLEN-1:0] sel_val;

  logic [XLEN-1:0] a_low_pipe_q [STAGES], a_low_pipe_d [STAGES];
  logic            b_msb_pipe_q [STAGES], b_msb_pipe_d [STAGES];
  logic [2:0]      subop_pipe_q [STAGES], subop_pipe_d [STAGES];
  logic [XLEN-1:0] b_full_pipe_q [STAGES], b_full_pipe_d [STAGES];
  // logic en_q;
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
  logic signed [31:0] a_signed;
   logic [XLEN-1:0] hi;
  logic [XLEN-1:0] corr;
  
  wire pipe_out_v = valid_pipe_q[STAGES-1];
  wire stall_out = pipe_out_v && buf_value_q && !resp_ready;
  wire adv_pipe = (|valid_pipe_q || (req_valid && !stall_out)) && !stall_out;
  wire req_fire = req_valid && !stall_out;

  always_comb begin
    a_d = a_q;
    b_d = b_q;
    if (req_fire) begin
      a_d = op_a;
      b_d = op_b;
    end
  end

  DW_mult_pipe #(
    .a_width      (XLEN),
    .b_width      (XLEN),
    .num_stages   (STAGES),
    .stall_mode   (1),
    .rst_mode     (1),
    .op_iso_mode  (0)
  ) U_mult_ss (
    .clk      (clk),
    .rst_n    (~rst),
    .en       (adv_pipe),
    .tc       (1'b1),
    .a        (a_q),
    .b        (b_q),
    .product  (prod_ss)
  );

  always_comb begin
    valid_pipe_d = valid_pipe_q;
    for (integer i = 0; i < STAGES; i++) begin
      rd_pipe_d[i] = rd_pipe_q[i];
      pd_pipe_d[i] = pd_pipe_q[i];
      rob_pipe_d[i] = rob_pipe_q[i];
      we_pipe_d[i] = we_pipe_q[i];
      a_low_pipe_d[i] = a_low_pipe_q[i];
      b_msb_pipe_d[i] = b_msb_pipe_q[i];
      subop_pipe_d[i] = subop_pipe_q[i];
      b_full_pipe_d[i] = b_full_pipe_q[i];
    end
    if (adv_pipe) begin
      for (integer i = STAGES-1; i > 0; i--) begin
        rd_pipe_d[i] = rd_pipe_q[i-1];
        pd_pipe_d[i] = pd_pipe_q[i-1];
        rob_pipe_d[i] = rob_pipe_q[i-1];
        we_pipe_d[i] = we_pipe_q[i-1];
        a_low_pipe_d[i] = a_low_pipe_q[i-1];
        b_msb_pipe_d[i] = b_msb_pipe_q[i-1];
        subop_pipe_d[i] = subop_pipe_q[i-1];
        b_full_pipe_d[i] = b_full_pipe_q[i-1];
      end
      if (req_fire) begin
        rd_pipe_d[0] = rd_arch;
        pd_pipe_d[0] = pd_phys;
        rob_pipe_d[0] = rob_idx;
        we_pipe_d[0] = dest_we;
        a_low_pipe_d[0] = op_a;
        b_msb_pipe_d[0] = op_b[XLEN-1];
        subop_pipe_d[0] = sub_op;
        b_full_pipe_d[0] = op_b;
      end
      valid_pipe_d = {valid_pipe_q[STAGES-2:0], req_fire};
    end
  end

  wire pop = buf_value_q && resp_ready;
  wire push = pipe_out_v && (!buf_value_q || resp_ready);

  always_comb begin
    buf_value_d = (buf_value_q & ~pop) | push;
    buf_val_d = buf_val_q;
    buf_rd_d = buf_rd_q;
    buf_pd_d = buf_pd_q;
    buf_rob_d = buf_rob_q;
    buf_we_d = buf_we_q;
    if (push) begin
      sel_val = prod_ss[31:0]; // default MUL
      unique case (subop_pipe_q[STAGES-1])
      3'b000: sel_val = prod_ss[31:0];    // MUL
      3'b001: sel_val = prod_ss[63:32];   // MULH (signed*signed)
      3'b010: begin  // MULHSU (high, signed*unsigned)

        hi   = prod_ss[63:32];                          // high 32 bits of signed*signed
        corr = b_msb_pipe_q[STAGES-1]
                ? a_low_pipe_q[STAGES-1]               // same bits as a_signed
                : '0;

        sel_val = hi + corr;                            // pure vector add, no signed types
      end
      3'b011: begin
        hi = prod_ss[63:32];
        sel_val = hi
                  + (a_low_pipe_q[STAGES-1][XLEN-1] ? b_full_pipe_q[STAGES-1] : '0)
                  + (b_msb_pipe_q[STAGES-1] ? a_low_pipe_q[STAGES-1] : '0);
      end
      default: /* keep default */;
    endcase
      buf_val_d = sel_val;
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
        a_low_pipe_q[i] <= '0;
        b_msb_pipe_q[i] <= 1'b0;
        subop_pipe_q[i] <= '0;
        b_full_pipe_q[i] <= '0;
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
        we_pipe_q[i]  <= we_pipe_d[i];
        a_low_pipe_q[i] <= a_low_pipe_d[i];
        b_msb_pipe_q[i] <= b_msb_pipe_d[i];
        subop_pipe_q[i] <= subop_pipe_d[i];
        b_full_pipe_q[i] <= b_full_pipe_d[i];
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
