// FreelistFIFO.sv — FIFO freelist specialized for physical-register IDs.
// - Dequeue at allocate (rename)
// - Enqueue at commit (RRAT free)
// - Preloaded contents on reset: p[LOG_REGS .. PHY_REGS-1]
// - Bypass on empty if enq & deq in same cycle.
// - On flush_valid (branch mispredict), behave like their free_list:
//   tail <= head; flip MSB => freelist becomes "full" again.

module FreelistFIFO
  import rv32i_types::*;
#(
  parameter integer LOG_REGS  = NUM_ARCH_REG,
  parameter integer PHY_REGS  = NUM_PHYS_REG,

  localparam integer WIDTH     = PHYS_REG_IDX+1,
  localparam integer DEPTH     = PHY_REGS - LOG_REGS
)(
  input  logic                  clk,
  input  logic                  rst,

  // Rename / Dispatch (dequeue)
  input  logic                  alloc_req,      // request PD
  output logic                  alloc_gnt,      // grant this cycle
  output logic [WIDTH-1:0]      pd_alloc,       // valid when alloc_gnt

  // RRAT / Commit (enqueue)
  input  logic                  free_valid,
  input  logic [WIDTH-1:0]      free_pd,

  // Status (optional)
  output logic                  full,
  output logic                  empty,
  output logic                  almost_empty,

  // Branch mispredict / flush (like branch_mispredict in their free_list)
  input  logic                  flush_valid
);

  // ----- Internals -----
  function integer calc_log2(input integer num);
    integer r; begin r=0; while ((1<<r)<num) r=r+1; return r; end
  endfunction

  localparam integer ADDR_WIDTH = calc_log2(DEPTH);
  localparam integer PTR_WIDTH  = ADDR_WIDTH + 1;               // extra MSB
  localparam logic [ADDR_WIDTH:0] DEPTH_U = DEPTH;
  localparam pd_t LOG_REGS_U = LOG_REGS;

  logic [WIDTH-1:0]          fifo [0:DEPTH-1];

  // head/tail with extra MSB (like their LENGTHEXP+1)
  logic [PTR_WIDTH-1:0]      head, tail;
  logic [ADDR_WIDTH:0]       count;          // still keep count for almost_empty

  wire [ADDR_WIDTH-1:0] head_idx = head[ADDR_WIDTH-1:0];
  wire [ADDR_WIDTH-1:0] tail_idx = tail[ADDR_WIDTH-1:0];

  // Peek (for normal non-empty pops)
  wire [WIDTH-1:0]           front = fifo[head_idx];

  // Status: same pattern as their free_list
  assign empty =
    (head_idx == tail_idx) && (head[PTR_WIDTH-1] == tail[PTR_WIDTH-1]);
  assign full  =
    (head_idx == tail_idx) && (head[PTR_WIDTH-1] != tail[PTR_WIDTH-1]);

  assign almost_empty = (count <= 2);

  // Illegal frees (never return architectural PDs)
  wire free_illegal   = (free_pd == '0);

  // Grant logic + outgoing PD (includes bypass when empty but free_valid+alloc_req)
  assign alloc_gnt = alloc_req &&
                     ( !empty || (empty && free_valid && !free_illegal) );

  assign pd_alloc  =
    (empty && free_valid && !free_illegal && alloc_req) ? free_pd : front;

  // ----- Main state machine -----
  always_ff @(posedge clk) begin
    if (rst) begin
      // Seed freelist with p[LOG_REGS .. PHY_REGS-1]
      for (integer i = 0; i < DEPTH; i++) begin
        fifo[i] <= pd_t'(LOG_REGS + i);
      end

      // Make the FIFO logically full at reset
      head  <= '0;
      // index 0, but MSB different from head -> full
      tail  <= {1'b1, {ADDR_WIDTH{1'b0}}};
      count <= DEPTH_U;

    end else if (flush_valid) begin
      // Do what their free_list does on branch_mispredict:
      //   tail <= head; flip MSB; queue becomes "full".
      tail  <= {~head[PTR_WIDTH-1], head_idx};
      count <= DEPTH_U;  // match the "full" condition

      // Note: FIFO contents unchanged; we're just treating all slots as free.

    end else begin
      // Case 1: BYPASS (empty & enq & deq & legal free) -> no storage update
      if (empty && free_valid && !free_illegal && alloc_req) begin
        // do nothing to fifo / pointers / count
      end
      else begin
        // Pop if requested and not empty
        if (alloc_req && !empty) begin
          head  <= head + {{(PTR_WIDTH-1){1'b0}}, 1'b1};
          count <= count - 1'b1;
        end

        // Push if valid, legal, and space (or we also popped this cycle)
        if (free_valid && !free_illegal) begin
          if (!full || (alloc_req && !empty)) begin
            fifo[tail_idx] <= free_pd;
            tail           <= tail + {{(PTR_WIDTH-1){1'b0}}, 1'b1};

            if (!(alloc_req && !empty)) begin
              count <= count + 1'b1;
            end
          end
          // else: full without pop -> drop (shouldn't happen)
        end
      end
    end
  end

endmodule
