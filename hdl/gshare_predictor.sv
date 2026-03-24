module gshare_predictor #(
    parameter integer GHR_BITS    = 10,
    parameter integer BHT_ENTRIES = 1024,
    localparam integer BHT_IDX_BITS = $clog2(BHT_ENTRIES)
) (
    input logic                     clk,
    input  logic                     rst,
    // Branch prediction interface
    input  logic [31:0]              pc,
    output logic                     predict_taken,
    output logic [BHT_IDX_BITS-1:0] bht_idx_out,
    // Update interface
    input  logic                     update_valid,
    input  logic [BHT_IDX_BITS-1:0]              update_bht_idx,
    input  logic                     update_taken // 1 for taken, 0 for not taken
);

    //Global History Register
    logic [GHR_BITS-1:0] ghr_q, ghr_d;
    typedef logic [1:0] bht_entry_t;
    bht_entry_t bht [BHT_ENTRIES];

    //make a increment counter and decmrent counter function
    function automatic bht_entry_t increment_counter(input bht_entry_t counter);
        case (counter)
            2'b00: increment_counter = 2'b01;
            2'b01: increment_counter = 2'b10;
            2'b10: increment_counter = 2'b11;
            default: increment_counter = 2'b11; // saturate at strongly taken
        endcase
    endfunction

    function automatic bht_entry_t decrement_counter(bht_entry_t counter);
         case (counter)
              2'b01: decrement_counter =  2'b00;
              2'b10: decrement_counter =  2'b01;
              2'b11: decrement_counter =  2'b10;
              default: decrement_counter = 2'b00;
         endcase
    endfunction

     // Use word-aligned PC bits as "PC index" (ignore bottom 2 bits) and XOR with GHR
    assign bht_idx_out = (pc[BHT_IDX_BITS+1:2]) ^ ghr_q[BHT_IDX_BITS-1:0];

    bht_entry_t ctr_f;
    assign ctr_f = bht[bht_idx_out];

    // Predict taken if MSB of counter is 1
    assign predict_taken = ctr_f[1];

    //decide the next GHR value combinationally
    always_comb begin
        ghr_d = ghr_q;
        if (update_valid) begin
            ghr_d = {ghr_q[GHR_BITS-2:0], 1'b1};
        end
    end

    // Sequential logic
    integer i;
    always_ff @(posedge clk) begin
        if(rst) begin 
            ghr_q <= '0;
            for (i = 0; i < BHT_ENTRIES; i++) begin
                bht[i] <= 2'b10; // Initialize to weakly taken
            end
        end else begin
            ghr_q <= ghr_d;
            if (update_valid) begin        
                if (update_taken) begin
                    bht[update_bht_idx] <= increment_counter(bht[update_bht_idx]);
                end else begin
                    bht[update_bht_idx] <= decrement_counter(bht[update_bht_idx]);
                end
            end
        end
    end

endmodule
