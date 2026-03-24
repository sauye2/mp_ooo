module provided_cache #(
    parameter integer SETS = 8,                 // must be power of 2
    parameter integer WAYS = 4                   // must be power of 2 (PLRU tree)
) (
    input   logic               clk,
    input   logic               rst,

    input   logic   [31:0]      ufp_addr,
    input   logic   [3:0]       ufp_rmask,
    input   logic   [3:0]       ufp_wmask,
    output  logic   [31:0]      ufp_rdata,
    input   logic   [31:0]      ufp_wdata,
    output  logic               ufp_resp,

    output  logic   [31:0]      dfp_addr,
    output  logic               dfp_read,
    output  logic               dfp_write,
    input   logic   [255:0]     dfp_rdata,
    output  logic   [255:0]     dfp_wdata,
    input   logic               dfp_resp
);

    // Address breakdown (32-b_yte line => 5 offset bits)
    // [31 : 5+SET_B_ITS]  tag
    // [5+SET_B_ITS-1 : 5] set index
    // [4:2]              word index within line
    localparam integer LINE_OFF_BITS = 5; // 32B lines
    localparam integer SET_BITS      = $clog2(SETS);
    localparam integer WAY_BITS      = $clog2(WAYS);
    localparam integer TAG_BITS      = 32 - LINE_OFF_BITS - SET_BITS;

    typedef logic [TAG_BITS-1:0] tag_t;
    typedef logic [WAY_BITS-1:0] way_t;

    wire [2:0] word_idx = ufp_addr[4:2];
    wire [SET_BITS-1:0] set_idx  = ufp_addr[LINE_OFF_BITS + SET_BITS - 1 : LINE_OFF_BITS];
    wire tag_t          tag_in   = ufp_addr[31 : LINE_OFF_BITS + SET_BITS];

    // aligned line base address
    wire [31:0] line_base_addr = {ufp_addr[31:LINE_OFF_BITS], {LINE_OFF_BITS{1'b0}}};

    // Cache arrays: [set][way]
    logic [255:0] data_q [SETS][WAYS];
    tag_t         tag_q  [SETS][WAYS];
    logic         valid_q[SETS][WAYS];

    // Tree-PLRU bits per set: WAYS-1 internal nodes
    logic [WAYS-2:0] plru_q[SETS];

    // FSM + pending request state (single outstanding miss)
    typedef enum logic [1:0] { IDLE, CHECK, LD, WR } state_t;
    state_t state_q, state_d;

    // Latch the request when leaving IDLE
    logic [31:0]    req_addr_q, req_addr_d;
    logic [3:0]     req_rmask_q, req_rmask_d;
    logic [3:0]     req_wmask_q, req_wmask_d;
    logic [31:0]    req_wdata_q, req_wdata_d;
    logic [2:0]     req_word_idx_q, req_word_idx_d;
    logic [SET_BITS-1:0] req_set_q, req_set_d;
    tag_t               req_tag_q, req_tag_d;
    logic               req_is_store_q, req_is_store_d;

    // victim/selected way for fills + writes
    logic [WAY_BITS-1:0] sel_way_q, sel_way_d;

    // write-through staging
    logic [31:0]  wr_addr_q, wr_addr_d;
    logic [255:0] wr_data_q, wr_data_d;

    // PLRU helper functions (power-of-2 ways)
    // Node indexing:
    // internal nodes: 0 .. WAYS-2
    // leaves are implicit; traversal ends after WAY_BITS steps
    function automatic integer unsigned plru_pick(input logic [WAYS-2:0] st);
        integer unsigned node;
        integer unsigned level;
        logic        dir;   

        node = 0;
        for (level = 0; level < WAY_BITS; level++) begin
            dir  = st[node];                    
            node = node*2 + 1 + integer'(dir);         // cast to integer for math
        end

        return node - (WAYS-1);
    endfunction


    function automatic logic [WAYS-2:0] plru_touch(
        input logic [WAYS-2:0] st,
        input way_t           way
    );
        logic [WAYS-2:0] ns;
        integer unsigned     node;
        integer unsigned     level;
        logic            dir;  

        ns   = st;
        node = 0;

        for (level = 0; level < WAY_BITS; level++) begin
            dir = way[$unsigned(WAY_BITS-1) - level];
            ns[node]= ~dir;                            
            node    = node*2 + 1 + integer'(dir);           // cast to integer for math
        end

        return ns;
    endfunction

    logic [SET_BITS-1:0] look_set;
    tag_t               look_tag;

    always_comb begin
        if (state_q == IDLE) begin
            look_set = set_idx;
            look_tag = tag_in;
        end else begin
            look_set = req_set_q;
            look_tag = req_tag_q;
        end
    end

    // Hit detection in the selected set
    logic hit;
    logic [WAY_BITS-1:0] hit_way;

    always_comb begin
        integer wi;
        hit = 1'b0;
        hit_way = '0;
        for (wi = 0; wi < WAYS; wi++) begin
            if (valid_q[look_set][wi] && (tag_q[look_set][wi] == look_tag)) begin
                hit = 1'b1;
                hit_way = way_t'(wi);
            end
        end
    end

    // victim selection (prefer invalid else PLRU)
    function automatic logic [WAY_BITS-1:0] pick_victim(
        input logic [WAYS-1:0] valid_vec_i,
        input logic [WAYS-2:0] plru_bits_i
    );
        integer unsigned vw;
        integer unsigned node;
        integer          level;
        logic            dir;
        logic            found;
        logic [WAY_BITS-1:0] res;
        begin
            res   = '0;
            found = 1'b0;

            // Prefer first invalid
            for (vw = 0; vw < WAYS; vw++) begin
                if (!valid_vec_i[vw] && !found) begin
                    res   = way_t'(vw);
                    found = 1'b1;
                end
            end

            // Else: PLRU pick (inline plru_pick to keep this function self-contained)
            if (!found) begin
                node = 0;
                for (level = 0; level < WAY_BITS; level++) begin
                    dir  = plru_bits_i[node];
                    node = (node << 1) + 32'd1 + (dir ? 32'd1 : 32'd0);
                end
                res = way_t'(node - $unsigned(WAYS-1));
            end

            pick_victim = res;
        end
    endfunction

    function automatic logic [255:0] merge_store(
        input logic [255:0] old_line,
        input logic [2:0]   word_i,
        input logic [3:0]   wmask,
        input logic [31:0]  wdata
    );
        logic [255:0] nl;
        logic [LINE_OFF_BITS-1:0] byte_base;
        integer unsigned b;
        begin
            nl = old_line;
            byte_base = {word_i, 2'b00};
            for (b = 0; b < 4; b++) begin
                if (wmask[b]) begin
                    nl[(byte_base+b)*8 +: 8] = wdata[b*8 +: 8];
                end
            end
            return nl;
        end
    endfunction
 
    logic [WAYS-1:0] valid_vec;

    // Main control
    always_comb begin
        // defaults
        state_d = state_q;

        ufp_rdata = '0;
        ufp_resp  = 1'b0;

        dfp_addr  = '0;
        dfp_read  = 1'b0;
        dfp_write = 1'b0;
        dfp_wdata = '0;

        req_addr_d      = req_addr_q;
        req_rmask_d     = req_rmask_q;
        req_wmask_d     = req_wmask_q;
        req_wdata_d     = req_wdata_q;
        req_word_idx_d  = req_word_idx_q;
        req_set_d       = req_set_q;
        req_tag_d       = req_tag_q;
        req_is_store_d  = req_is_store_q;

        sel_way_d       = sel_way_q;
        wr_addr_d       = wr_addr_q;
        wr_data_d       = wr_data_q;

        unique case (state_q)
            IDLE: begin
                if (|ufp_rmask || |ufp_wmask) begin
                    // latch request
                    req_addr_d      = ufp_addr;
                    req_rmask_d     = ufp_rmask;
                    req_wmask_d     = ufp_wmask;
                    req_wdata_d     = ufp_wdata;
                    req_word_idx_d  = ufp_addr[4:2];
                    req_set_d       = set_idx;
                    req_tag_d       = tag_in;
                    req_is_store_d  = (|ufp_wmask);
                    state_d         = CHECK;
                end
            end

            CHECK: begin
                if (hit) begin
                    // LOAD hit
                    if (|req_rmask_q) begin
                        ufp_rdata = data_q[req_set_q][hit_way][req_word_idx_q*32 +: 32];
                        if (!req_is_store_q) begin
                            ufp_resp = 1'b1;
                            state_d  = IDLE;
                        end
                    end

                    // STORE hit: update line + write-through
                    if (|req_wmask_q) begin
                        logic [255:0] new_line;
                        new_line = merge_store(
                            data_q[req_set_q][hit_way],
                            req_word_idx_q,
                            req_wmask_q,
                            req_wdata_q
                        );

                        dfp_addr  = {req_tag_q, req_set_q, {LINE_OFF_BITS{1'b0}}};
                        dfp_write = 1'b1;
                        dfp_wdata = new_line;

                        wr_addr_d = dfp_addr;
                        wr_data_d = new_line;
                        sel_way_d = hit_way;
                        state_d   = WR;
                    end
                end else begin
                    // miss: pick victim and go read line
                    integer wj;
                    valid_vec = '0;
                    for (wj = 0; wj < WAYS; wj++) begin
                        valid_vec[wj] = valid_q[req_set_q][wj];
                    end

                    sel_way_d = pick_victim(valid_vec, plru_q[req_set_q]);
                    state_d   = LD;
                end
            end

            LD: begin
                dfp_addr = {req_tag_q, req_set_q, {LINE_OFF_BITS{1'b0}}};

                if (!dfp_resp) begin
                    dfp_read = 1'b1;
                end else begin
                    logic [255:0] fill_line;
                    fill_line = dfp_rdata;

                    if (|req_wmask_q) begin
                        fill_line = merge_store(fill_line, req_word_idx_q, req_wmask_q, req_wdata_q);

                        // stage write-through for WR state (NO dfp_write here)
                        wr_addr_d = dfp_addr;
                        wr_data_d = fill_line;
                        state_d   = WR;
                    end else begin
                        ufp_rdata = fill_line[req_word_idx_q*32 +: 32];
                        ufp_resp  = 1'b1;
                        state_d   = IDLE;
                    end
                end
            end

            WR: begin
                dfp_write = 1'b1;
                dfp_addr  = wr_addr_q;
                dfp_wdata = wr_data_q;

                if (dfp_resp) begin
                    ufp_resp = 1'b1;
                    state_d  = IDLE;
                end
            end

            default: state_d = IDLE;
        endcase
    end

    // Sequential: update arrays + PLRU + request regs
    integer s, ww;
    always_ff @(posedge clk) begin
        if (rst) begin
            state_q <= IDLE;

            req_addr_q     <= '0;
            req_rmask_q    <= '0;
            req_wmask_q    <= '0;
            req_wdata_q    <= '0;
            req_word_idx_q <= '0;
            req_set_q      <= '0;
            req_tag_q      <= '0;
            req_is_store_q <= 1'b0;

            sel_way_q      <= '0;
            wr_addr_q      <= '0;
            wr_data_q      <= '0;

            for (s = 0; s < SETS; s++) begin
                plru_q[s] <= '0;
                for (ww = 0; ww < WAYS; ww++) begin
                    valid_q[s][ww] <= 1'b0;
                    tag_q[s][ww]   <= '0;
                    data_q[s][ww]  <= '0;
                end
            end
        end else begin
            state_q <= state_d;

            req_addr_q     <= req_addr_d;
            req_rmask_q    <= req_rmask_d;
            req_wmask_q    <= req_wmask_d;
            req_wdata_q    <= req_wdata_d;
            req_word_idx_q <= req_word_idx_d;
            req_set_q      <= req_set_d;
            req_tag_q      <= req_tag_d;
            req_is_store_q <= req_is_store_d;

            sel_way_q      <= sel_way_d;
            wr_addr_q      <= wr_addr_d;
            wr_data_q      <= wr_data_d;

            // On hit in CHECK: update PLRU + data for store hit (we update when WR commits)
            if (state_q == CHECK && hit) begin
                plru_q[req_set_q] <= plru_touch(plru_q[req_set_q], hit_way);
            end

            // On fill completion in LD: allocate line into victim way
            if (state_q == LD && dfp_resp) begin
                logic [255:0] fill_line;
                fill_line = dfp_rdata;

                if (|req_wmask_q) begin
                    fill_line = merge_store(fill_line, req_word_idx_q, req_wmask_q, req_wdata_q);
                end

                data_q[req_set_q][sel_way_q]  <= fill_line;
                tag_q[req_set_q][sel_way_q]   <= req_tag_q;
                valid_q[req_set_q][sel_way_q] <= 1'b1;

                plru_q[req_set_q] <= plru_touch(plru_q[req_set_q], sel_way_q);
            end

            // On store hit, once WR completes we should also update the cached line
            // (since write-through uses wr_data_q as the merged line)
            if (state_q == WR && dfp_resp) begin
                // only meaningful if the request was a store
                if (req_is_store_q) begin
                    data_q[req_set_q][sel_way_q]  <= wr_data_q;
                    tag_q[req_set_q][sel_way_q]   <= req_tag_q;
                    valid_q[req_set_q][sel_way_q] <= 1'b1;
                end
            end
        end
    end

endmodule
