module stream_buffer #(
    parameter SB_DEPTH = 4
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        invalidate,
    input  logic        req_valid,
    input  logic [31:0] req_addr,
    output logic        req_ready,
    output logic        resp_valid,
    output logic [31:0] resp_data,
    output logic        mem_req_valid,
    output logic [31:0] mem_req_addr,
    input  logic        mem_req_ready,
    input  logic        mem_resp_valid,
    input  logic [31:0] mem_resp_data
);
    localparam SB_CNT_W = $clog2(SB_DEPTH) + 1;
    localparam SB_IDX_W = (SB_DEPTH == 1) ? 1 : $clog2(SB_DEPTH);

    logic demand_pending_q, demand_pending_d;
    logic demand_from_sb_q, demand_from_sb_d;
    logic demand_mem_issued_q, demand_mem_issued_d;
    logic [31:0] demand_addr_q, demand_addr_d;
    logic [31:0] sb_resp_data_q, sb_resp_data_d;
    logic mem_pending_q, mem_pending_d;
    logic mem_is_demand_q, mem_is_demand_d;
    logic [31:0] mem_addr_q, mem_addr_d;
    logic stream_active_q, stream_active_d;
    logic [31:0] stream_next_q, stream_next_d;

    logic unused_mem_req_ready;
    assign unused_mem_req_ready = mem_req_ready;

    logic [31:0] sb_addr_q [SB_DEPTH];
    logic [31:0] sb_addr_d [SB_DEPTH];
    logic [31:0] sb_data_q [SB_DEPTH];
    logic [31:0] sb_data_d [SB_DEPTH];
    logic [SB_DEPTH-1:0] sb_valid_q, sb_valid_d;
    logic [SB_CNT_W-1:0] sb_count_q, sb_count_d;
    logic [SB_IDX_W-1:0] sb_head_q, sb_head_d;
    logic [SB_IDX_W-1:0] sb_tail_q, sb_tail_d;

    logic sb_has_head;
    logic [31:0] sb_head_addr;
    assign sb_has_head = (sb_count_q != 0);
    assign sb_head_addr = sb_addr_q[sb_head_q];

    // demand can issue only when no outstanding demand response is owed
    assign req_ready = ~demand_pending_q;

    wire [SB_CNT_W-1:0] SB_DEPTH_W = SB_CNT_W'($unsigned(SB_DEPTH));

    // prefetch condition: have a stream and room in FIFO
    logic want_prefetch;
    assign want_prefetch = stream_active_q && (sb_count_q < SB_DEPTH_W);

    logic start_mem;
    logic start_mem_is_demand;
    logic [31:0] start_mem_addr;

    // demand priority over prefetch
    logic has_old_demand_needing_issue;
    logic has_new_demand_needing_issue;
    logic demand_needs_issue;
    logic [31:0] demand_issue_addr;
    logic accept_req;
    logic hit_head;

    integer i;
    always_comb begin
        demand_pending_d = demand_pending_q;
        demand_from_sb_d = demand_from_sb_q;
        demand_mem_issued_d = demand_mem_issued_q;
        demand_addr_d = demand_addr_q;
        sb_resp_data_d = sb_resp_data_q;
        mem_pending_d = mem_pending_q;
        mem_is_demand_d = mem_is_demand_q;
        mem_addr_d = mem_addr_q;
        stream_active_d = stream_active_q;
        stream_next_d = stream_next_q;
        sb_valid_d = sb_valid_q;
        sb_head_d = sb_head_q;
        sb_tail_d = sb_tail_q;
        sb_count_d = sb_count_q;
        for (i = 0; i < SB_DEPTH; i = i + 1) begin
            sb_addr_d[i] = sb_addr_q[i];
            sb_data_d[i] = sb_data_q[i];
        end

        resp_valid          = 1'b0;
        resp_data           = 32'd0;
        start_mem           = 1'b0;
        start_mem_is_demand = 1'b0;
        start_mem_addr      = 32'd0;

        // accept new demand from IF
        accept_req = req_valid && req_ready;
        hit_head = sb_has_head && (sb_head_addr == req_addr);
        if (accept_req) begin
            demand_pending_d = 1'b1;
            demand_addr_d = req_addr;
            demand_mem_issued_d = 1'b0;
            if (hit_head) begin
                demand_from_sb_d = 1'b1;
                sb_resp_data_d = sb_data_q[sb_head_q];
            end else begin
                demand_from_sb_d = 1'b0;
            end
        end

        // hit response
        if (demand_pending_q && demand_from_sb_q) begin
            resp_valid = 1'b1;
            resp_data = sb_resp_data_q;
            demand_pending_d = 1'b0;
            demand_from_sb_d = 1'b0;
            demand_mem_issued_d = 1'b0;
            if (sb_count_q != 0) begin
                sb_valid_d[sb_head_q] = 1'b0;
                sb_head_d  = sb_head_q + 1'b1;
                sb_count_d = sb_count_q - 1'b1;
            end
        end

        // mem response
        if (mem_resp_valid && mem_pending_q) begin
            mem_pending_d = 1'b0;
            if (mem_is_demand_q) begin
                resp_valid = 1'b1;
                resp_data = mem_resp_data;
                demand_pending_d = 1'b0;
                demand_mem_issued_d = 1'b0;
                stream_active_d = 1'b1;
                stream_next_d = mem_addr_q + 32'd4;
            end else begin
                if (sb_count_q < SB_DEPTH_W) begin
                    sb_addr_d[sb_tail_q] = mem_addr_q;
                    sb_data_d[sb_tail_q] = mem_resp_data;
                    sb_valid_d[sb_tail_q] = 1'b1;
                    sb_tail_d = sb_tail_q + 1'b1;
                    sb_count_d = sb_count_q + 1'b1;
                    stream_next_d = mem_addr_q + 32'd4;
                end
                // else buffer full so drop this prefetch
            end
        end

        has_old_demand_needing_issue = demand_pending_q && !demand_from_sb_q && !demand_mem_issued_q;
        has_new_demand_needing_issue = accept_req && !hit_head;
        demand_needs_issue = has_old_demand_needing_issue || has_new_demand_needing_issue;
        if (has_old_demand_needing_issue) begin
            demand_issue_addr = demand_addr_q;
        end else if (has_new_demand_needing_issue) begin
            demand_issue_addr = req_addr;
        end else begin
            demand_issue_addr = 32'd0;
        end
        if (!mem_pending_q) begin
            if (demand_needs_issue) begin                // demand has prio over prefetch
                start_mem = 1'b1;
                start_mem_addr = demand_issue_addr;
                start_mem_is_demand = 1'b1;
                demand_mem_issued_d = 1'b1;
            end else if (want_prefetch) begin
                start_mem = 1'b1;
                start_mem_addr = stream_next_q;
                start_mem_is_demand = 1'b0;
            end
        end
        if (start_mem) begin
            mem_pending_d = 1'b1;
            mem_is_demand_d = start_mem_is_demand;
            mem_addr_d = start_mem_addr;
        end
        // drive mem request outputs
        mem_req_valid = mem_pending_q || start_mem;
        mem_req_addr = mem_pending_q ? mem_addr_q : start_mem_addr;
        if (invalidate) begin                                         // invalidate on flush
            stream_active_d = 1'b0;
            stream_next_d = 32'd0;
            sb_valid_d = '0;
            sb_head_d = '0;
            sb_tail_d = '0;
            sb_count_d = '0;
        end
    end

    integer j;
    always_ff @(posedge clk) begin
        if (rst) begin
            demand_pending_q <= 1'b0;
            demand_from_sb_q <= 1'b0;
            demand_mem_issued_q <= 1'b0;
            demand_addr_q <= 32'd0;
            sb_resp_data_q <= 32'd0;
            mem_pending_q <= 1'b0;
            mem_is_demand_q <= 1'b0;
            mem_addr_q <= 32'd0;
            stream_active_q <= 1'b0;
            stream_next_q   <= 32'd0;
            sb_valid_q <= '0;
            sb_head_q  <= '0;
            sb_tail_q  <= '0;
            sb_count_q <= '0;
            for (j = 0; j < SB_DEPTH; j = j + 1) begin
                sb_addr_q[j] <= 32'd0;
                sb_data_q[j] <= 32'd0;
            end
        end else begin
            demand_pending_q <= demand_pending_d;
            demand_from_sb_q <= demand_from_sb_d;
            demand_mem_issued_q <= demand_mem_issued_d;
            demand_addr_q <= demand_addr_d;
            sb_resp_data_q <= sb_resp_data_d;
            mem_pending_q <= mem_pending_d;
            mem_is_demand_q <= mem_is_demand_d;
            mem_addr_q <= mem_addr_d;
            stream_active_q <= stream_active_d;
            stream_next_q <= stream_next_d;
            sb_valid_q <= sb_valid_d;
            sb_head_q <= sb_head_d;
            sb_tail_q <= sb_tail_d;
            sb_count_q <= sb_count_d;
            for (j = 0; j < SB_DEPTH; j = j + 1) begin
                sb_addr_q[j] <= sb_addr_d[j];
                sb_data_q[j] <= sb_data_d[j];
            end
        end
    end

endmodule
