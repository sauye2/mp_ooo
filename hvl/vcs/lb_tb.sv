`timescale 1ns/1ps

module lb_tb;

    logic clk = 0;
    logic rst = 1;

    logic fill_valid;
    logic [31:0] fill_addr;
    logic [255:0] fill_data;

    logic invalidate;
    logic [31:0] req_pc;

    logic hit;
    logic [31:0] word;

    linebuffer dut (
        .clk        (clk),
        .rst        (rst),
        .fill_valid (fill_valid),
        .fill_addr  (fill_addr),
        .fill_data  (fill_data),
        .invalidate (invalidate),
        .req_pc     (req_pc),
        .hit        (hit),
        .word       (word)
    );

    // clock
    always #5 clk = ~clk;

    // helper to build a cache line with incremental words
    function automatic [255:0] build_line(input logic [31:0] base);
        build_line = '0;
        for (int i = 0; i < 8; i++) begin
            build_line[i*32 +: 32] = base + i;
        end
    endfunction

    task automatic expect_hit(input logic exp_hit, input logic [31:0] exp_word, string msg);
        #1; // allow combinational propagation
        if (hit !== exp_hit) begin
            $fatal(1, "[%0t] %s: expected hit=%0d, got %0d", $time, msg, exp_hit, hit);
        end
        if (exp_hit && word !== exp_word) begin
            $fatal(1, "[%0t] %s: expected word=0x%08h, got 0x%08h", $time, msg, exp_word, word);
        end
    endtask

    initial begin
        $fsdbDumpfile("dump.fsdb");
        $fsdbDumpvars(0, "+all");
        fill_valid  = 0;
        fill_addr   = '0;
        fill_data   = '0;
        invalidate  = 0;
        req_pc      = '0;

        // reset
        repeat (3) @(posedge clk);
        rst = 0;
        @(posedge clk);

        // no line loaded yet -> miss
        req_pc = 32'h0000_0010;
        expect_hit(1'b0, 32'hXXXX_XXXX, "cold miss");

        // fill cache line aligned at 0x0000_0000
        fill_addr  = 32'h0000_0000;
        fill_data  = build_line(32'hA5A5_0000);
        fill_valid = 1'b1;
        @(posedge clk);
        fill_valid = 1'b0;

        // should now hit each word
        for (int i = 0; i < 8; i++) begin
            req_pc = fill_addr + (i * 4);
            expect_hit(1'b1, 32'hA5A5_0000 + i, $sformatf("hit word %0d", i));
        end

        // different line -> miss
        req_pc = 32'h0000_0100;
        expect_hit(1'b0, 32'hXXXX_XXXX, "different line miss");

        // invalidate and ensure miss again
        invalidate = 1'b1;
        @(posedge clk);
        invalidate = 1'b0;
        req_pc = 32'h0000_0000;
        expect_hit(1'b0, 32'hXXXX_XXXX, "post-invalidate miss");

        $display("[%0t] linebuffer TB passed.", $time);
        $finish;
    end

endmodule