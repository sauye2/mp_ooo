module if_stage
#(
    parameter logic ENABLE_RAS = 1'b1
)
(
    input  logic         clk,
    input  logic         rst,

    input  logic         redirect_valid,
    input  logic [31:0]  redirect_pc,

    // To IQ
    output logic         inst_valid,
    output logic [31:0]  inst,
    output logic [31:0]  inst_pc,
    input  logic         inst_ready,

    // I-cache
    output logic         icache_req_valid,
    output logic [31:0]  icache_req_addr,
    input  logic         icache_req_ready,

    input  logic [31:0]  icache_resp_data,
    input  logic         icache_resp_valid,

    // Prediction metadata to pipeline
    output logic         inst_pred_taken,
    output logic [7:0]   inst_bht_idx,
    output logic [31:0]  inst_pred_target,

    // GShare update from commit
    input  logic         bpred_update_valid,
    input  logic [7:0]   bpred_update_idx,
    input  logic         bpred_update_taken,

    // BTB update inputs
    input  logic         btb_update_valid,
    input  logic [31:0]  btb_update_pc,
    input  logic [31:0]  btb_update_target
);

    // --- GShare predictor parameters ---
    localparam integer GHR_BITS      = 8;
    localparam integer BHT_ENTRIES   = 256;
    localparam integer BHT_IDX_BITS  = $clog2(BHT_ENTRIES);

    // --- BTB params ---
    localparam integer BTB_ENTRIES   = 32;
    localparam integer BTB_IDX_BITS  = $clog2(BTB_ENTRIES);

    // --- GShare fetch-side wires ---
    logic                    predict_taken_f;
    logic [BHT_IDX_BITS-1:0] bht_idx_f;

    // pipeline registers to hold prediction info
    logic                    predict_taken_q, predict_taken_d;
    logic [BHT_IDX_BITS-1:0] bht_idx_q,      bht_idx_d;
    logic [31:0]             inst_pred_target_q, inst_pred_target_d;
    logic                    taken_pred;

    // BTB
    typedef struct packed {
        logic        valid;
        logic [31:0] tag;
        logic [31:0] target;
    } btb_entry_t;

    btb_entry_t btb [BTB_ENTRIES];

    // BTB lookup signals
    logic [BTB_IDX_BITS-1:0] btb_idx_f;
    logic                    btb_hit_f;
    logic [31:0]             btb_target_f;
    logic [BTB_IDX_BITS-1:0] btb_update_idx;
    btb_entry_t              btb_rd_f;

    // FSM
    typedef enum logic [1:0] {
        FETCH_IDLE,
        FETCH_REQ,
        FETCH_WAIT
    } fetch_state_t;

    fetch_state_t fetch_state_q, fetch_state_d;

    logic [31:0] pc_q, pc_d;

    logic [31:0] inst_q, inst_d;
    logic        inst_valid_q, inst_valid_d;
    logic [31:0] inst_pc_q, inst_pc_d;

    logic [31:0] addr_aligned;
    logic        slot_free;

    logic        hold_valid_q, hold_valid_d;
    logic [31:0] hold_data_q,  hold_data_d;

    // small frontend-decode temporaries
    logic [31:0] inst_f;
    logic [6:0]  opcode_f;
    logic [31:0] b_imm_f;
    logic        is_branch_f;
    logic [31:0] br_target_f;
    logic [31:0] pc_plus4_local, pc_pred_local;
    logic        is_jalr_f;
    logic        is_jal_f;
    logic [31:0] j_imm_f;
    logic [31:0] jal_target_f;
    logic [4:0]  rd_f, rs1_f;
    logic [2:0]  funct3_f;
    logic [11:0] i_imm_f;

    // RAS helpers (table: link regs x1/x5)
    logic        rd_is_link, rs1_is_link, rd_eq_rs1;

    // --- Return Address Stack (RAS) ---
    logic        ras_push;
    logic [31:0] ras_push_addr;
    logic        ras_pop;
    logic [31:0] ras_top_addr;
    logic        ras_empty;

    // Outputs
    assign inst             = inst_q;
    assign inst_pc          = inst_pc_q;
    assign inst_valid       = inst_valid_q;
    assign inst_pred_taken  = predict_taken_q;
    assign inst_bht_idx     = bht_idx_q;
    assign inst_pred_target = inst_pred_target_q;

    assign addr_aligned = {pc_q[31:2], 2'b0};
    assign slot_free    = !inst_valid_q || inst_ready;

    // --- BTB lookup (ENABLED) ---
    assign btb_idx_f      = pc_q[BTB_IDX_BITS+1 : 2];
    assign btb_update_idx = btb_update_pc[BTB_IDX_BITS+1 : 2];

    always_comb begin
        btb_rd_f     = btb[btb_idx_f];
        btb_hit_f    = btb_rd_f.valid && (btb_rd_f.tag == pc_q); // tag = full PC
        btb_target_f = btb_rd_f.target;
    end

    // --- GShare predictor ---
    gshare_predictor #(
        .GHR_BITS    (GHR_BITS),
        .BHT_ENTRIES (BHT_ENTRIES)
    ) gshare_predictor_inst (
        .clk            (clk),
        .rst            (rst),
        .pc             (pc_q),
        .predict_taken  (predict_taken_f),
        .bht_idx_out    (bht_idx_f),
        .update_valid   (bpred_update_valid),
        .update_bht_idx (bpred_update_idx),
        .update_taken   (bpred_update_taken)
    );

    // --- RAS instance ---
    return_address_stack #(
        .DEPTH (8),
        .XLEN  (32)
    ) u_ras (
        .clk       (clk),
        .rst       (rst),
        .flush     (redirect_valid),
        .push      (ras_push),
        .push_addr (ras_push_addr),
        .pop       (ras_pop),
        .top_addr  (ras_top_addr),
        .empty     (ras_empty)
    );

    // --- Combinational next-state ---
    always_comb begin
        pc_d          = pc_q;
        fetch_state_d = fetch_state_q;

        inst_d        = inst_q;
        inst_pc_d     = inst_pc_q;
        inst_valid_d  = inst_valid_q;

        icache_req_valid = 1'b0;
        icache_req_addr  = addr_aligned;

        hold_valid_d     = hold_valid_q;
        hold_data_d      = hold_data_q;

        // prediction meta defaults
        predict_taken_d      = predict_taken_q;
        bht_idx_d            = bht_idx_q;
        inst_pred_target_d   = inst_pred_target_q;

        // RAS defaults
        ras_push      = 1'b0;
        ras_push_addr = '0;
        ras_pop       = 1'b0;

        // other helper defaults
        taken_pred    = 1'b0;

        // retire instruction when IQ accepts it
        if (inst_valid_q && inst_ready) begin
            inst_valid_d        = 1'b0;
            predict_taken_d     = 1'b0;
            bht_idx_d           = '0;
            inst_pred_target_d  = '0;
        end

        if (redirect_valid) begin
            pc_d          = redirect_pc;
            fetch_state_d = FETCH_IDLE;
            inst_valid_d  = 1'b0;
            hold_valid_d  = 1'b0;

            predict_taken_d     = 1'b0;
            bht_idx_d           = '0;
            inst_pred_target_d  = '0;

        end else begin
            unique case (fetch_state_q)
                FETCH_IDLE: begin
                    if (slot_free) begin
                        icache_req_valid = 1'b1;
                        icache_req_addr  = addr_aligned;
                        if (icache_req_ready) begin
                            fetch_state_d = FETCH_WAIT;
                        end
                    end
                end

                FETCH_REQ: begin
                    fetch_state_d = FETCH_IDLE;
                end

                FETCH_WAIT: begin
                    // ---------------------------
                    // Case 1: direct I-cache hit
                    // ---------------------------
                    if (icache_resp_valid) begin
                        if (slot_free) begin
                            inst_f      = icache_resp_data;
                            opcode_f    = inst_f[6:0];

                            b_imm_f     = {{20{inst_f[31]}}, inst_f[7], inst_f[30:25],
                                           inst_f[11:8], 1'b0};
                            j_imm_f     = {{12{inst_f[31]}}, inst_f[19:12],
                                           inst_f[20], inst_f[30:21], 1'b0};
                            is_branch_f = (opcode_f == 7'b1100011);
                            is_jalr_f   = (opcode_f == 7'b1100111);
                            is_jal_f    = (opcode_f == 7'b1101111);

                            rd_f        = inst_f[11:7];
                            rs1_f       = inst_f[19:15];
                            funct3_f    = inst_f[14:12];
                            i_imm_f     = inst_f[31:20];

                            // link regs per table: x1/x5
                            rd_is_link  = (rd_f  == 5'd1) || (rd_f  == 5'd5);
                            rs1_is_link = (rs1_f == 5'd1) || (rs1_f == 5'd5);
                            rd_eq_rs1   = (rd_f  == rs1_f);

                            pc_plus4_local = pc_q + 32'd4;
                            br_target_f    = pc_q + b_imm_f;
                            jal_target_f   = pc_q + j_imm_f;

                            // =========================================
                            // RAS ACTION TABLE (applied for JAL/JALR)
                            // rd_is_link, rs1_is_link, rd_eq_rs1
                            // =========================================
                            if (is_jal_f || is_jalr_f) begin
                                // row: rd !link, rs1 !link → None
                                if (!rd_is_link && rs1_is_link) begin
                                    // row: rd !link, rs1 link → Pop
                                    ras_pop = 1'b1;
                                end
                                else if (rd_is_link && !rs1_is_link) begin
                                    // row: rd link, rs1 !link → Push
                                    ras_push = 1'b1;
                                end
                                else if (rd_is_link && rs1_is_link && !rd_eq_rs1) begin
                                    // row: rd link, rs1 link, rd!=rs1 → Pop then Push
                                    ras_pop  = 1'b1;
                                    ras_push = 1'b1;
                                end
                                else if (rd_is_link && rs1_is_link && rd_eq_rs1) begin
                                    // row: rd link, rs1 link, rd==rs1 → Push
                                    ras_push = 1'b1;
                                end

                                if (ras_push) begin
                                    ras_push_addr = pc_plus4_local; // return address
                                end
                            end

                            // =========================================
                            // BRANCH / JUMP PREDICTION + RAS for RETs
                            // =========================================
                            pc_pred_local = pc_plus4_local;
                            if (is_branch_f || is_jal_f || is_jalr_f) begin
                                taken_pred = predict_taken_f || is_jal_f || is_jalr_f;
                                if (taken_pred) begin
                                    // JALR using link reg → RET-like, use RAS top
                                    if (is_jalr_f && rs1_is_link && !ras_empty && ENABLE_RAS) begin
                                        pc_pred_local = ras_top_addr;
                                    end
                                    else if (btb_hit_f) begin
                                        pc_pred_local = btb_target_f;
                                    end
                                    else if (is_jal_f) begin
                                        pc_pred_local = jal_target_f;
                                    end
                                    else if (is_branch_f) begin
                                        pc_pred_local = br_target_f;
                                    end
                                    else begin
                                        pc_pred_local = pc_plus4_local;
                                    end
                                end
                            end

                            // drive IF -> IQ outputs
                            inst_d       = icache_resp_data;
                            inst_pc_d    = pc_q;
                            inst_valid_d = 1'b1;

                            // record prediction metadata actually used
                            predict_taken_d    = taken_pred;
                            bht_idx_d          = bht_idx_f;
                            inst_pred_target_d = pc_pred_local;

                            // steer PC to predicted place
                            pc_d          = pc_pred_local;

                            hold_valid_d   = 1'b0;
                            fetch_state_d  = FETCH_IDLE;
                        end else begin
                            // IQ not ready, buffer the line
                            hold_data_d  = icache_resp_data;
                            hold_valid_d = 1'b1;
                        end

                    // ---------------------------
                    // Case 2: using buffered data
                    // ---------------------------
                    end else if (hold_valid_q && slot_free) begin
                        inst_f      = hold_data_q;
                        opcode_f    = inst_f[6:0];

                        b_imm_f     = {{20{inst_f[31]}}, inst_f[7], inst_f[30:25],
                                       inst_f[11:8], 1'b0};
                        j_imm_f     = {{12{inst_f[31]}}, inst_f[19:12],
                                       inst_f[20], inst_f[30:21], 1'b0};
                        is_branch_f = (opcode_f == 7'b1100011);
                        is_jalr_f   = (opcode_f == 7'b1100111);
                        is_jal_f    = (opcode_f == 7'b1101111);

                        rd_f        = inst_f[11:7];
                        rs1_f       = inst_f[19:15];
                        funct3_f    = inst_f[14:12];
                        i_imm_f     = inst_f[31:20];

                        rd_is_link  = (rd_f  == 5'd1) || (rd_f  == 5'd5);
                        rs1_is_link = (rs1_f == 5'd1) || (rs1_f == 5'd5);
                        rd_eq_rs1   = (rd_f  == rs1_f);

                        pc_plus4_local = pc_q + 32'd4;
                        br_target_f    = pc_q + b_imm_f;
                        jal_target_f   = pc_q + j_imm_f;

                        // RAS TABLE again for buffered inst
                        if (is_jal_f || is_jalr_f) begin
                            if (!rd_is_link && rs1_is_link) begin
                                ras_pop = 1'b1;
                            end
                            else if (rd_is_link && !rs1_is_link) begin
                                ras_push = 1'b1;
                            end
                            else if (rd_is_link && rs1_is_link && !rd_eq_rs1) begin
                                ras_pop  = 1'b1;
                                ras_push = 1'b1;
                            end
                            else if (rd_is_link && rs1_is_link && rd_eq_rs1) begin
                                ras_push = 1'b1;
                            end

                            if (ras_push) begin
                                ras_push_addr = pc_plus4_local;
                            end
                        end

                        pc_pred_local = pc_plus4_local;
                        if (is_branch_f || is_jal_f || is_jalr_f) begin
                            taken_pred = predict_taken_f || is_jal_f || is_jalr_f;
                            if (taken_pred) begin
                                if (is_jalr_f && rs1_is_link && !ras_empty && ENABLE_RAS) begin
                                    pc_pred_local = ras_top_addr;
                                end
                                else if (btb_hit_f) begin
                                    pc_pred_local = btb_target_f;
                                end
                                else if (is_jal_f) begin
                                    pc_pred_local = jal_target_f;
                                end
                                else if (is_branch_f) begin
                                    pc_pred_local = br_target_f;
                                end
                                else begin
                                    pc_pred_local = pc_plus4_local;
                                end
                            end
                        end

                        inst_d       = hold_data_q;
                        inst_pc_d    = pc_q;
                        inst_valid_d = 1'b1;

                        predict_taken_d    = taken_pred;
                        bht_idx_d          = bht_idx_f;
                        inst_pred_target_d = pc_pred_local;

                        pc_d          = pc_pred_local;

                        hold_valid_d   = 1'b0;
                        fetch_state_d  = FETCH_IDLE;
                    end
                end

                default: fetch_state_d = FETCH_IDLE;
            endcase
        end
    end

    // --- Sequential state ---
    integer i;
    always_ff @(posedge clk) begin
        if (rst) begin
            pc_q          <= 32'haaaaa000;
            fetch_state_q <= FETCH_IDLE;
            inst_q        <= '0;
            inst_pc_q     <= '0;
            inst_valid_q  <= 1'b0;
            hold_valid_q  <= 1'b0;
            hold_data_q   <= '0;
            predict_taken_q     <= 1'b0;
            bht_idx_q           <= '0;
            inst_pred_target_q  <= '0;

            // Clear BTB
            for (i = 0; i < BTB_ENTRIES; i = i + 1) begin
                btb[i].valid  <= 1'b0;
                btb[i].tag    <= '0;
                btb[i].target <= '0;
            end

        end else begin
            // BTB write
            if (btb_update_valid) begin
                btb[btb_update_idx].valid  <= 1'b1;
                btb[btb_update_idx].tag    <= btb_update_pc;
                btb[btb_update_idx].target <= btb_update_target;
            end

            pc_q          <= pc_d;
            fetch_state_q <= fetch_state_d;
            inst_q        <= inst_d;
            inst_pc_q     <= inst_pc_d;
            inst_valid_q  <= inst_valid_d;
            hold_valid_q  <= hold_valid_d;
            hold_data_q   <= hold_data_d;
            predict_taken_q     <= predict_taken_d;
            bht_idx_q           <= bht_idx_d;
            inst_pred_target_q  <= inst_pred_target_d;
        end
    end

endmodule : if_stage
