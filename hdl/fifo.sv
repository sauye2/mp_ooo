module fifo_queue #(parameter DEPTH = 8, parameter WIDTH = 32)      // fifo with parameterizable depth and width (8x32 for 256 bts)
(
    input  logic             clk,
    input  logic             rst,
    input  logic             enq,        // enqueue element
    input  logic             deq,        // dequeue element
    input  logic [WIDTH-1:0] d_in,       // fifo input
    output logic [WIDTH-1:0] d_out,      // fifo output
    output logic             full,       // fifo full checker
    output logic             empty,       // fifo empty checker
    input  logic             flush
);
    
    function integer calc_log2(input integer num);
      integer r;
      begin
        r = 0;
        while ((1 << r) < num)
          r = r + 1;
        return r;
      end
    endfunction
    localparam integer ADDR_WIDTH = calc_log2(DEPTH);
    localparam logic [ADDR_WIDTH:0] DEPTH_U = DEPTH;
    localparam [ADDR_WIDTH-1:0] last_idx = DEPTH - 1;
    logic [WIDTH-1:0] fifo [0:DEPTH-1];      // fifo array to hold data
    logic [ADDR_WIDTH-1:0] head;
    logic [ADDR_WIDTH-1:0] tail;
    logic [ADDR_WIDTH:0] count;
    assign d_out = fifo[head];
    assign full = (count == DEPTH_U);
    assign empty = (count == '0);

    always_ff @(posedge clk) begin
        if(rst) begin
            head <= '0;
            tail <= '0;
            count <= '0;
        end
        else begin
            if (flush) begin
                head <= '0;
                tail <= '0;
                count <= '0;
            end else if(!empty && enq && deq) begin          // simultaneous enqueue and dequeue
                fifo[tail] <= d_in;
                tail <= (tail == last_idx) ? '0 : tail + 1'b1;
                head <= (head == last_idx) ? '0 : head + 1'b1;
            end
            else if(!full && enq) begin            // push and fifo not full
                fifo[tail] <= d_in;
                tail <= (tail == last_idx) ? '0 : tail + 1'b1;   // behavior of circular fifo (when tail = last_idx, go back to 0)
                count <= count + 1'b1;
            end
            else if(!empty && deq) begin                         // pop and fifo is not empty
                head <= (head == last_idx) ? '0 : head + 1'b1;   // behavior of circular fifo (when head = last_idx, go back to 0)
                count <= count - 1'b1;
            end
        end
    end
endmodule : fifo_queue
