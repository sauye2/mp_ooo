module cacheline_adapter #(
  parameter LINE_BYTES = 32,
  parameter BEAT_BYTES = 8,
  parameter BEATS      = LINE_BYTES / BEAT_BYTES
)(
  input  logic         clk,
  input  logic         rst,

  input  logic [31:0]  dfp_addr,
  input  logic         dfp_read,
  input logic         dfp_write,
  input logic [255:0] dfp_wdata,
  output logic [255:0] dfp_rdata,
  output logic         dfp_resp,

  output logic [31:0]  bmem_addr,
  output logic         bmem_write,
  output logic [63:0]  bmem_wdata,
  output logic         bmem_read,
  input  logic         bmem_ready,
  input  logic [63:0]  bmem_rdata,
  input  logic         bmem_rvalid
);

  typedef enum logic [1:0] { IDLE, S_RD_REQ, S_RD_COLLECT, S_WR_SEND } state_t;
  localparam logic [1:0] BEATS_MINUS_ONE = BEATS - 1;
  localparam integer BEAT_SHIFT = $clog2(BEAT_BYTES);
  state_t       state, next_state;
  logic [1:0]   beat_count, next_beat_count;
  logic [255:0] rdata_buffer, next_rdata_buffer;
  logic [31:0]  cur_addr, next_addr;
  logic [255:0] wdata_buffer;
  logic [255:0] next_wdata_buffer;


  always_ff @(posedge clk) begin
    if (rst) begin
      state        <= IDLE;
      beat_count   <= '0;
      rdata_buffer <= '0;
      cur_addr     <= '0;
      wdata_buffer <= '0;
    end else begin
      state        <= next_state;
      beat_count   <= next_beat_count;
      rdata_buffer <= next_rdata_buffer;
      cur_addr     <= next_addr;
      wdata_buffer <= next_wdata_buffer;
    end
  end

  always_comb begin
    bmem_addr         = cur_addr;
    bmem_read         = 1'b0;
    dfp_rdata         = rdata_buffer;
    dfp_resp          = 1'b0;

    next_state        = state;
    next_beat_count   = beat_count;
    next_rdata_buffer = rdata_buffer;
    next_wdata_buffer = wdata_buffer;
    next_addr         = cur_addr;
    bmem_wdata        = '0;
    bmem_write        = 1'b0;

    unique case (state)
      IDLE: begin
        next_beat_count   = '0;
        if (dfp_read) begin
          next_addr         = {dfp_addr[31:5], 5'b0};
          next_rdata_buffer = '0;
          next_state        = S_RD_REQ;
        end
        else if (dfp_write) begin
          next_addr         = {dfp_addr[31:5], 5'b0};
          next_wdata_buffer = dfp_wdata;
          next_state        = S_WR_SEND;
          next_beat_count   = '0;
        end
      end

      S_RD_REQ: begin
        bmem_read = 1'b1;
        bmem_addr = cur_addr;
        if (bmem_ready) begin
          next_state      = S_RD_COLLECT;
          next_beat_count = '0;
        end
      end

      S_RD_COLLECT: begin
        // bmem_read = 1'b1;
        if (bmem_rvalid) begin
          next_rdata_buffer[(beat_count*64) +: 64] = bmem_rdata;
          if (beat_count == BEATS_MINUS_ONE) begin
            dfp_rdata  = next_rdata_buffer;
            dfp_resp   = 1'b1;
            next_state = IDLE;
          end
          next_beat_count = beat_count + 1'b1;
        end
      end

      S_WR_SEND: begin
        bmem_write = 1'b1;
        bmem_addr  = cur_addr;
        bmem_wdata = wdata_buffer[(beat_count*64) +: 64]; // drive current beat

      // advance only when backing mem accepts the beat
      if (bmem_ready) begin
        if (beat_count == BEATS_MINUS_ONE) begin
          dfp_resp  = 1'b1;   // last beat accepted
          next_state = IDLE;
        end
        next_beat_count = beat_count + 1'b1;
      end
    end

    default: begin
      next_state = IDLE;
    end
    endcase
  end
endmodule
