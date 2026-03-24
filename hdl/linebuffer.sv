module linebuffer (
    input  logic         clk,
    input  logic         rst,

    input  logic         fill_valid,
    input  logic [31:0]  fill_addr,   // b_yte address of returned beat
    input  logic [255:0] fill_data,   // one-hot word in its slot

    input  logic         invalidate,

    input  logic [31:0]  req_pc,
    output logic         hit,
    output logic [31:0]  word
);

    logic        valid_q, valid_d;
    logic [31:5] tag_q,   tag_d;
    logic [255:0] data_q, data_d;
    logic [7:0]  word_valid_q, word_valid_d;

    wire [31:5] req_tag = req_pc[31:5];
    wire [2:0]  req_idx = req_pc[4:2];
    wire [2:0]  fill_idx = fill_addr[4:2];
    wire [7:0]  fill_mask = 8'b1 << fill_idx;

    assign hit  = valid_q && (tag_q == req_tag) && word_valid_q[req_idx];
    assign word = hit ? data_q[req_idx*32 +: 32] : 32'b0;

    always_comb begin
        valid_d      = valid_q;
        tag_d        = tag_q;
        data_d       = data_q;
        word_valid_d = word_valid_q;

        if (invalidate) begin
            valid_d      = 1'b0;
            word_valid_d = '0;
        end else if (fill_valid) begin
            // if new tag, start a fresh line
            if (!valid_q || (tag_q != fill_addr[31:5])) begin
                tag_d        = fill_addr[31:5];
                data_d       = '0;
                word_valid_d = '0;
                valid_d      = 1'b1;
            end
            // merge this beat into the line
            data_d[fill_idx*32 +: 32] = fill_data[fill_idx*32 +: 32];
            word_valid_d = word_valid_d | fill_mask;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_q      <= 1'b0;
            tag_q        <= '0;
            data_q       <= '0;
            word_valid_q <= '0;
        end else begin
            valid_q      <= valid_d;
            tag_q        <= tag_d;
            data_q       <= data_d;
            word_valid_q <= word_valid_d;
        end
    end
endmodule