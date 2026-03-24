module nl_prefetcher (
    input  logic         clk,
    input  logic         rst,

    // Demand side (from IF)
    input  logic         dem_req_valid,
    input  logic [31:0]  dem_req_addr,
    output logic         dem_req_ready,
    output logic         dem_resp_valid,
    output logic [31:0]  dem_resp_data,

    input logic dem_miss_seen,

    // Memory side (to cache/adapter)
    output logic         mem_req_valid,
    output logic [31:0]  mem_req_addr,
    input  logic         mem_req_ready,
    input  logic         mem_resp_valid,
    input  logic [31:0]  mem_resp_data
);
    // track active request
    logic        req_pending_q, req_pending_d;
    logic [31:0] req_addr_q,    req_addr_d;
    logic        req_is_pf_q,   req_is_pf_d;

    // pending prefetch
    logic        pf_pending_q, pf_pending_d;
    logic [31:0] pf_addr_q,    pf_addr_d;

    logic [31:0] next_line;
    logic [255:0] pf_buf_q, pf_buf_d;
    logic [2:0] pf_idx_q, pf_idx_d;

    // fire when IF issues and we’re free
    wire dem_fire = dem_req_valid && dem_req_ready;
    wire issue_demand = dem_req_valid && !req_pending_q;
    wire issue_pf     = pf_pending_q && !req_pending_q && !issue_demand;

    logic dem_miss_q, dem_miss_d;

    // combinational
    always_comb begin
        // defaults
        req_pending_d   = req_pending_q;
        req_addr_d      = req_addr_q;
        req_is_pf_d     = req_is_pf_q;
        pf_pending_d    = pf_pending_q;
        pf_addr_d       = pf_addr_q;
        pf_buf_d      = pf_buf_q;
        pf_idx_d      = pf_idx_q;

        mem_req_valid  = req_pending_q || issue_demand || issue_pf;
        mem_req_addr   = req_pending_q ? req_addr_q : issue_demand ? dem_req_addr : pf_addr_q;

        dem_resp_valid  = 1'b0;
        dem_resp_data   = mem_resp_data;

        // only ready when downstream ready and no active request
        dem_req_ready   = mem_req_ready && !req_pending_q;

        // launch demand
        if (!req_pending_q && mem_req_ready && (issue_demand || issue_pf)) begin
            req_pending_d = 1'b1;
            // starting a new transaction: clear miss marker
            dem_miss_d = 1'b0;
            req_addr_d    = issue_demand ? dem_req_addr : pf_addr_q;
            req_is_pf_d   = issue_pf;
            if (issue_pf) begin
                pf_pending_d = 1'b0; // consumed prefetch
                pf_buf_d     = 256'b0;
                pf_idx_d     = 3'b0;
            end
        end

        if (req_pending_q && !req_is_pf_q && dem_miss_seen) begin
            dem_miss_d = 1'b1;
        end

        // response handling
        if (mem_resp_valid && req_pending_q) begin
            req_pending_d = 1'b0;
            if (!req_is_pf_q) begin
                dem_resp_valid = 1'b1;
                // compute next-line prefetch (same page)
                next_line = {req_addr_q[31:5] + 27'd1, 5'b0};
                if (dem_miss_q && (req_addr_q[31:12] == next_line[31:12]) && !pf_pending_q) begin
                    pf_pending_d = 1'b1;
                    pf_addr_d    = next_line;   // request word 0 of next line
                end
            end else begin
                // accumulate 8 beats of 32b into a 256b line
                pf_buf_d[pf_idx_q*32 +: 32] = mem_resp_data;
                if (pf_idx_q == 3'd7) begin
                    pf_idx_d      = 3'd0;
                    pf_buf_d      = '0;
                end else begin
                    pf_idx_d = pf_idx_q + 3'd1;
                end
            end
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            req_pending_q <= 1'b0;
            req_addr_q    <= '0;
            req_is_pf_q   <= 1'b0;
            pf_pending_q  <= 1'b0;
            pf_addr_q     <= '0;
            pf_buf_q     <= 256'b0;
            pf_idx_q     <= 3'b0;
            dem_miss_q <= 1'b0;
        end else begin
            req_pending_q <= req_pending_d;
            req_addr_q    <= req_addr_d;
            req_is_pf_q   <= req_is_pf_d;
            pf_pending_q  <= pf_pending_d;
            pf_addr_q     <= pf_addr_d;
            pf_buf_q     <= pf_buf_d;
            pf_idx_q     <= pf_idx_d;
            dem_miss_q <= dem_miss_d;
        end
    end
endmodule
