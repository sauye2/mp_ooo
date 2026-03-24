module fifo_tb;

  parameter DEPTH = 8;
  parameter WIDTH = 32;
  logic clk;
  logic rst;
  logic enq;
  logic deq;
  logic [WIDTH-1:0] d_in;
  logic [WIDTH-1:0] d_out;
  logic full;
  logic empty;
  
  // instantiate fifo
  fifo_queue #(DEPTH, WIDTH) dut (
    .clk(clk),
    .rst(rst),
    .enq(enq),
    .deq(deq),
    .d_in(d_in),
    .d_out(d_out),
    .full(full),
    .empty(empty)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end
  
  initial begin
    $display("\nStarting FIFO TB");
    rst = 1'b1;
    enq = 1'b0;
    deq = 1'b0;
    d_in = '0;
    #10;
    rst = 1'b0;
    #10;
    
    $display("Test 1: Check initial conditions");
    if(empty)
      $display("PASS: FIFO is empty after rst.");
    else
      $display("FAIL: FIFO is not empty after rst.");

    $display("\nTest 2: Make sure FIFO principle is true");
    @(posedge clk);
    enq = 1'b1;
    d_in = 32'h11111111;
    $display("Push #1: %h", d_in);
    @(posedge clk); 
    enq = 1'b0;
    @(posedge clk);
    enq = 1'b1;
    d_in = 32'h22222222;
    $display("Push #2: %h", d_in);
    @(posedge clk); 
    enq = 1'b0;
    @(posedge clk);
    enq = 1'b1;
    d_in = 32'h33333333;
    $display("Push #3: %h", d_in);
    @(posedge clk); 
    enq = 1'b0;

    @(posedge clk);
    deq = 1'b1;
    $display("Pop #1 Expected: 11111111, Actual: %h", d_out);
    @(posedge clk);
    deq = 1'b0;
    @(posedge clk);
    deq = 1'b1;
    $display("Pop #2 Expected: 22222222, Actual: %h", d_out);
    @(posedge clk);
    deq = 1'b0;
    @(posedge clk);
    deq = 1'b1;
    $display("Pop #3 Expected: 33333333, Actual: %h", d_out);
    @(posedge clk);
    deq = 1'b0;
    
    $display("\nTest 3: Push Until Full & Overflow Attempt");
    rst = 1'b1;
    #10;
    rst = 1'b0;
    #10;
    for(int i = 0; i < DEPTH; i++) begin
      @(posedge clk);
      enq = 1'b1;
      d_in = i;
      @(posedge clk);
      enq = 1'b0;
      $display("Push #%0d", i + 1);
    end
    @(posedge clk);
    if(full)
      $display("PASS: FIFO is full as it should be");
    else
      $display("FAIL: FIFO is not full when it should be");
    
    // overflow attempt by pushing when full
    @(posedge clk);
    enq = 1'b1;
    d_in = 32'hFFFFFFFF;
    @(posedge clk);
    enq = 1'b0;
    $display("Push #%0d", 9);
    if(full)
      $display("PASS: Overflow treatment as expected");
    else
      $display("FAIL: Overflow treatment not as expected");
    
    $display("\nTest 4: Pop Until Empty & Underflow Attempt");
    for (int i = 0; i < DEPTH; i++) begin
      @(posedge clk);
      deq = 1'b1;
      @(posedge clk);
      $display("Pop #%0d", i + 1);
      deq = 1'b0;
    end
    if(empty)
      $display("PASS: FIFO is empty as it should be");
    else
      $display("FAIL: FIFO is not empty when it should be");
    
    // overflow attempt by popping when empty
    @(posedge clk);
    deq = 1'b1;
    @(posedge clk);
    deq = 1'b0;
    $display("Pop #%0d", 9);
    if(empty)
      $display("PASS: Underflow treatment as expected");
    else
      $display("FAIL: Underflow treatment not as expected");
    
    $display("\nTest 5: Simultaneous push and pop");
    for(int i = 0; i < DEPTH; i++) begin
      @(posedge clk);
      enq = 1'b1;
      d_in = i + 1;
      @(posedge clk);
      enq = 1'b0;
      $display("Push #%0d", i + 1);
    end
    $display("\nAsserting simultaenous push and pop when FIFO is full");
    for(int i = 0; i < 3; i++) begin
      @(posedge clk);
      enq = 1'b1;
      deq = 1'b1;
      d_in = i + 20;
      @(posedge clk);
      enq = 1'b0;
      deq = 1'b0;
      $display("Push #%0d", i + 1);
      $display("Pop #%0d", i + 1);
    end
    if(full)
      $display("PASS: Simultaneous push and pop behavior as expected");
    else
      $display("FAIL: Simultaneous push and pop behavior not as expected");
    
    $display("\nTest 6: Wrap-around behavior");
    while(!empty) begin
      @(posedge clk);
      deq = 1'b1;
      @(posedge clk);
      deq = 1'b0;
    end
    for(int i = 0; i < 5; i++) begin
      @(posedge clk);
      enq = 1'b1;
      d_in = i + 30;
      @(posedge clk);
      enq = 1'b0;
    end
    for(int i = 0; i < 2; i++) begin
      @(posedge clk);
      deq = 1'b1;
      @(posedge clk);
      deq = 1'b0;
    end
    for(int i = 0; i < 4; i++) begin
      @(posedge clk);
      enq = 1'b1;
      d_in = i + 40;
      @(posedge clk);
      enq = 1'b0;
    end
    if(!full)
      $display("FIFO is not full");
    else
      $display("FIFO is full");     
    @(posedge clk);
    enq = 1'b1;
    d_in = 32'hFFFFFFFF;
    @(posedge clk);
    enq = 1'b0;
    if(full)
      $display("PASS: Wrap-around behavior is correct");
    else
      $display("FAIL: Wrap-around behavior is incorrect");
    while(!empty) begin
      @(posedge clk);
      deq = 1'b1;
      @(posedge clk);
      deq = 1'b0;
    end
    
    $display("\nTest 7: Reset behavior mid operation");
    for (int i = 0; i < 3; i++) begin
      @(posedge clk);
      enq = 1'b1;
      d_in = i + 50;
      @(posedge clk);
      enq = 1'b0;
    end
    @(posedge clk);
    rst = 1'b1;
    @(posedge clk);
    rst = 1'b0;
    if(empty)
      $display("PASS: FIFO is empty after rst during operation.");
    else
      $display("FAIL: FIFO is not empty after rst during operation.");
    #10;
    $finish;
  end

endmodule : fifo_tb
