module return_address_stack #(
    parameter integer DEPTH = 8,
    parameter integer XLEN  = 32
)(
    input  logic           clk,
    input  logic           rst,
    // flush on redirect / mispredict
    input  logic           flush,
    // ush a return address (PC+4 of call)
    input  logic           push,
    input  logic [XLEN-1:0] push_addr,
    //pop on RET
    input  logic           pop,
    output logic [XLEN-1:0] top_addr,
    output logic           empty
);
    localparam integer PTR_BITS = $clog2(DEPTH);
    logic [XLEN-1:0] stack [DEPTH-1:0];
    logic [PTR_BITS:0] sp_q, sp_d;
    localparam logic [PTR_BITS:0] DEPTH_VAL = DEPTH;
    logic [PTR_BITS-1:0] top_idx;

    assign empty = (sp_q == '0);
    assign top_idx  = (sp_q == '0) ? '0 : (sp_q[PTR_BITS-1:0] - 1'b1);
    assign top_addr = stack[top_idx];

    // pointer next-state
    always_comb begin
      sp_d = sp_q;
      if (push && !pop) begin
        if (sp_q < DEPTH_VAL)
          sp_d = sp_q + 1'b1;
      end else if (pop && !push) begin
        if (sp_q > '0)
          sp_d = sp_q - 1'b1;
      end
    end

    integer i;
    always_ff @(posedge clk) begin
      if (rst || flush) begin
        sp_q <= '0;
        for (i = 0; i < DEPTH; i++) begin
          stack[i] <= '0;
        end
      end else begin
        // write current top, then update pointer
        if (push && (sp_q < DEPTH_VAL)) begin
          stack[sp_q[PTR_BITS-1:0]] <= push_addr;
        end
        sp_q <= sp_d;
      end
    end

endmodule
