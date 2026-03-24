module cpu
import rv32i_types::*;
(
    input   logic               clk,
    input   logic               rst,

    output  logic   [31:0]      bmem_addr,
    output  logic               bmem_read,
    output  logic               bmem_write,
    output  logic   [63:0]      bmem_wdata,
    input   logic               bmem_ready,

    input   logic   [31:0]      bmem_raddr,
    input   logic   [63:0]      bmem_rdata,
    input   logic               bmem_rvalid
);

logic unused;
assign unused = |bmem_raddr;

// test 
logic [31:0] ufp_addr;
logic [3:0]  ufp_rmask;
logic [3:0]  ufp_wmask;
logic [31:0] ufp_wdata;
logic [31:0] ufp_rdata;
logic        ufp_resp;

logic [31:0] dfp_addr;
logic dfp_read;
logic dfp_write;
logic [255:0] dfp_wdata;
logic [255:0] dfp_rdata;
logic        dfp_resp;
logic flush_valid_r;

logic [31:0]  i_dfp_addr, d_dfp_addr;
logic         i_dfp_read, d_dfp_read;
logic         i_dfp_write, d_dfp_write;
logic [255:0] i_dfp_wdata, d_dfp_wdata;
logic [255:0] i_dfp_rdata, d_dfp_rdata;
logic         i_dfp_resp,  d_dfp_resp;

logic pf_fill_valid;
logic [31:0] pf_fill_addr;
logic [255:0] pf_fill_data;

logic [31:0] dcache_req_addr;
logic [3:0] dcache_rmask, dcache_wmask;
logic [31:0] dcache_wdata, dcache_rdata;
logic dcache_resp;
logic flush_valid;
logic is_jalr;

logic bpred_update_valid;
logic [7:0] bpred_update_idx;
logic bpred_update_taken;
logic if_pred_taken;
logic [31:0] if_pred_target;
logic [7:0] if_bht_idx;

ROB_to_RRF_t  rob_to_rrf;
RRF_to_ROB_t  rrf_to_rob;
logic         rob_full, rob_empty;
logic         commit_valid;
logic commit_branch_taken;

localparam integer BHT_IDX_BITS = 8;
localparam integer IQ_WIDTH     = 32 + 32 + 32 + 1 + BHT_IDX_BITS;

// ============================================================================
// PCSB SIGNALS
// ============================================================================
logic        pcsb_enq_valid;
logic        pcsb_enq_ready;
logic [31:0] pcsb_enq_addr;
logic [3:0]  pcsb_enq_wmask;
logic [31:0] pcsb_enq_wdata;

logic [31:0] pcsb_drain_addr;
logic [3:0]  pcsb_drain_wmask;
logic [31:0] pcsb_drain_wdata;
logic        pcsb_drain_valid;
logic        pcsb_drain_ready;
logic        pcsb_drain_resp;
logic        pcsb_empty;
logic        pcsb_full;

// PCSB forwarding signals
logic [31:0] pcsb_fwd_addr;
logic [3:0]  pcsb_fwd_rmask;
logic        pcsb_fwd_full_hit;
logic        pcsb_fwd_partial;
logic [31:0] pcsb_fwd_data;

// D-cache arbiter signals
logic [31:0] lsq_dcache_addr;
logic [3:0]  lsq_dcache_rmask;
logic [3:0]  lsq_dcache_wmask;
logic [31:0] lsq_dcache_wdata;
logic        dcache_lsq_resp;
logic        dcache_pcsb_resp;

typedef enum logic {ARB_LSQ, ARB_PCSB} dcache_owner_e;
dcache_owner_e dcache_owner_q, dcache_owner_d;
logic dcache_busy_q, dcache_busy_d;

// ============================================================================

provided_cache #(8, 4)i_cache (
    .clk        (clk),
    .rst        (rst),

    .ufp_addr   (ufp_addr),
    .ufp_rmask  (ufp_rmask),
    .ufp_wmask  (4'd0),
    .ufp_wdata  (32'd0),
    .ufp_rdata  (ufp_rdata),
    .ufp_resp   (ufp_resp),

    .dfp_addr   (i_dfp_addr),
    .dfp_read   (i_dfp_read),
    .dfp_write  (i_dfp_write),
    .dfp_wdata  (i_dfp_wdata),
    .dfp_rdata  (i_dfp_rdata),
    .dfp_resp   (i_dfp_resp)
);

provided_cache #(8, 4)d_cache (
  .clk(clk),
  .rst(rst),
  
  .ufp_addr  (dcache_req_addr),
  .ufp_rmask (dcache_rmask),
  .ufp_wmask (dcache_wmask),
  .ufp_wdata (dcache_wdata),
  .ufp_rdata (dcache_rdata),
  .ufp_resp  (dcache_resp),

  .dfp_addr  (d_dfp_addr),
  .dfp_read  (d_dfp_read),
  .dfp_write (d_dfp_write),
  .dfp_wdata (d_dfp_wdata),
  .dfp_rdata (d_dfp_rdata),
  .dfp_resp  (d_dfp_resp)
);

typedef enum logic {ICACHE, DCACHE} cachetype;
cachetype owner_q, owner_d;
logic rr_q, rr_d;
logic busy_q, busy_d;

always_comb begin
  owner_d = owner_q;
  rr_d    = rr_q;
  busy_d  = busy_q;
  dfp_addr  = (owner_q == ICACHE) ? i_dfp_addr  : d_dfp_addr;
  dfp_read  = (owner_q == ICACHE) ? i_dfp_read  : d_dfp_read;
  dfp_write = (owner_q == ICACHE) ? i_dfp_write : d_dfp_write;
  dfp_wdata = (owner_q == ICACHE) ? i_dfp_wdata : d_dfp_wdata;
  i_dfp_rdata = (owner_q == ICACHE) ? dfp_rdata : '0;
  d_dfp_rdata = (owner_q == DCACHE) ? dfp_rdata : '0;
  i_dfp_resp  = (owner_q == ICACHE) ? dfp_resp  : 1'b0;
  d_dfp_resp  = (owner_q == DCACHE) ? dfp_resp  : 1'b0;

  if (!busy_q && ((owner_q == ICACHE && (i_dfp_read|i_dfp_write)) || (owner_q == DCACHE && (d_dfp_read|d_dfp_write)))) begin
    busy_d = 1'b1;
  end
  if (dfp_resp) begin
    busy_d = 1'b0;
  end
  if ((!busy_q)) begin
    if ((owner_q == ICACHE && !(i_dfp_read | i_dfp_write)) || (owner_q == DCACHE && !(d_dfp_read | d_dfp_write))) begin
      if ((i_dfp_read | i_dfp_write) && (d_dfp_read | d_dfp_write)) begin
        owner_d = rr_q ? ICACHE : DCACHE;
      end
      else if (i_dfp_read | i_dfp_write) begin
        owner_d = ICACHE;
      end
      else if (d_dfp_read|d_dfp_write) begin
        owner_d = DCACHE;
      end
    end
  end
  if (dfp_resp && (i_dfp_read | i_dfp_write) && (d_dfp_read | d_dfp_write)) begin
    rr_d = ~rr_q;
  end
end

always_ff @(posedge clk) begin
  if (rst) begin 
    owner_q <= ICACHE;
    rr_q <= 1'b0;
    busy_q <= 1'b0;
  end else begin
    owner_q <= owner_d;
    rr_q <= rr_d;
    busy_q <= busy_d;
  end
end

logic commit_is_load, commit_is_store;
logic [2:0] f3;
logic [31:0] i_imm_commit, s_imm_commit, store_ea, load_ea;
logic lsq_enq_ready;
logic lsq_commit_ready;

logic [31:0] commit_inst;
logic [31:0] commit_pc;
logic [6:0]  commit_opcode;
logic [2:0]  commit_funct3;
logic [31:0] commit_rs1_val;
logic [31:0] commit_rs2_val;

logic [31:0] commit_i_imm_bra;   // I-imm for jalr
logic [31:0] commit_b_imm;       // B-imm for branches
logic [31:0] commit_j_imm;       // J-imm for jal

logic        commit_is_branch;
logic        commit_is_jal;
logic        commit_is_jalr;
logic        commit_br_taken;
logic [31:0] commit_next_pc;
logic        commit_pred_taken;
logic [31:0] commit_pred_target;
logic commit_actual_taken;
logic mispredict;
logic commit_br_delayed;

assign commit_pred_taken  = rob_to_rrf.rob_entry.pred_taken;
assign commit_pred_target = rob_to_rrf.rob_entry.pred_target;

logic [63:0] commit_order;
assign commit_order = rob_to_rrf.rob_entry.order;

logic branch_dir_mispredict;
assign branch_dir_mispredict =
    commit_is_branch &&
    (commit_valid && (commit_pred_taken != commit_br_taken));

assign commit_actual_taken =
    (commit_is_branch && commit_br_taken) ||
    commit_is_jal ||
    commit_is_jalr;

always_comb begin
  if(commit_is_branch && commit_valid) begin
    mispredict = (commit_pred_taken != (commit_br_taken));
  end else if ((commit_is_jal || commit_is_jalr) && commit_valid) begin
    mispredict = (commit_pred_target != commit_next_pc);
  end else begin
    mispredict = 1'b0;
  end
end

always_ff @(posedge clk) begin
  if (rst) begin
    commit_br_delayed <= 1'b0;
  end else begin
    commit_br_delayed <= commit_br_taken;
  end
end

assign commit_inst    = rob_to_rrf.rob_entry.inst;
assign commit_pc      = rob_to_rrf.rob_entry.pc;
assign commit_opcode  = rob_to_rrf.rob_entry.opcode;
assign commit_funct3  = commit_inst[14:12];
assign commit_rs1_val = rob_to_rrf.rob_entry.rs1_value;
assign commit_rs2_val = rob_to_rrf.rob_entry.rs2_value;

assign commit_i_imm_bra = {{21{commit_inst[31]}}, commit_inst[30:20]};
assign commit_b_imm  = {{20{commit_inst[31]}}, commit_inst[7], commit_inst[30:25], commit_inst[11:8], 1'b0};
assign commit_j_imm     = {{12{commit_inst[31]}},
                           commit_inst[19:12],
                           commit_inst[20],
                           commit_inst[30:21],
                           1'b0};

assign commit_is_branch = (commit_opcode == rv32i_types::op_b_br);
assign commit_is_jal    = (commit_opcode == rv32i_types::op_b_jal);
assign commit_is_jalr   = (commit_opcode == rv32i_types::op_b_jalr);

always_comb begin
  commit_br_taken = 1'b0;

  if (commit_is_branch) begin
    unique case (commit_funct3)
      3'b000: commit_br_taken = (commit_rs1_val == commit_rs2_val);
      3'b001: commit_br_taken = (commit_rs1_val != commit_rs2_val);
      3'b100: commit_br_taken = ($signed(commit_rs1_val) <  $signed(commit_rs2_val));
      3'b101: commit_br_taken = ($signed(commit_rs1_val) >= $signed(commit_rs2_val));
      3'b110: commit_br_taken = (commit_rs1_val <  commit_rs2_val);
      3'b111: commit_br_taken = (commit_rs1_val >= commit_rs2_val);
      default: commit_br_taken = 1'b0;
    endcase
  end
end

always_comb begin
  commit_next_pc = commit_pc + 32'd4;

  if (commit_is_branch) begin
    if (commit_br_taken)
      commit_next_pc = commit_pc + commit_b_imm;
    else
      commit_next_pc = commit_pc + 32'd4;
  end else if (commit_is_jal) begin
    commit_next_pc = commit_pc + commit_j_imm;
  end else if (commit_is_jalr) begin
    commit_next_pc = (commit_rs1_val + commit_i_imm_bra) & 32'hFFFF_FFFE;
  end
end

cacheline_adapter i_cacheline_adapter (
    .clk        (clk),
    .rst        (rst),

    .dfp_addr   (dfp_addr),
    .dfp_read   (dfp_read),
    .dfp_rdata  (dfp_rdata),
    .dfp_resp   (dfp_resp), 
    .dfp_write  (dfp_write),
    .dfp_wdata  (dfp_wdata),

    .bmem_addr  (bmem_addr),
    .bmem_read  (bmem_read),
    .bmem_ready (bmem_ready),
    .bmem_write (bmem_write),
    .bmem_wdata (bmem_wdata),
    .bmem_rdata (bmem_rdata),
    .bmem_rvalid(bmem_rvalid)
);

logic btb_update_valid;
logic [31:0] btb_update_pc;
logic [31:0] btb_update_target;
logic commit_ctrl_takes;

assign commit_ctrl_takes =
    (commit_is_branch && commit_branch_taken) ||
    commit_is_jal ||
    commit_is_jalr;

assign btb_update_valid  = commit_valid && commit_ctrl_takes;
assign btb_update_pc     = commit_pc;
assign btb_update_target = commit_next_pc;

// FETCH

logic if_inst_valid, if_inst_ready;
logic [31:0] if_inst, if_pc;
logic fifo_enq, fifo_deq, full, empty;
logic [IQ_WIDTH-1:0] fifo_d_in, fifo_d_out;

logic redirect_valid;
logic [31:0] redirect_pc;
logic is_branch;

assign if_inst_ready = !full;

assign fifo_enq = if_inst_valid && !full;
assign fifo_d_in = {if_pred_taken, if_bht_idx, if_pred_target, if_pc, if_inst};

logic icache_req_valid;
logic [31:0] icache_req_addr;
logic icache_req_ready;
logic icache_resp_valid;
logic [31:0] icache_resp_data;

logic ic_mem_req_valid;
logic [31:0] ic_mem_req_addr;

// logic dem_resp_valid;
// logic [31:0] dem_resp_data;
// logic dem_req_ready;

// nl_prefetcher u_nl_pf (
//     .clk            (clk),
//     .rst            (rst),
//     // demand from IF
//     .dem_req_valid  (icache_req_valid),
//     .dem_req_addr   (icache_req_addr),
//     .dem_req_ready  (dem_req_ready),
//     .dem_resp_valid (dem_resp_valid),
//     .dem_resp_data  (dem_resp_data),
//     // memory side
//     .mem_req_valid  (ic_mem_req_valid),
//     .mem_req_addr   (ic_mem_req_addr),
//     .mem_req_ready  (1'b1),
//     .mem_resp_valid (ufp_resp),
//     .mem_resp_data  (ufp_rdata),

//     .dem_miss_seen  (i_dfp_read && !flush_valid)
// );

stream_buffer u_stream_buffer (
    .clk          (clk),
    .rst          (rst),
    .invalidate   (flush_valid),

    // IF side
    .req_valid    (icache_req_valid),
    .req_addr     (icache_req_addr),
    .req_ready    (icache_req_ready),
    .resp_valid   (icache_resp_valid),
    .resp_data    (icache_resp_data),

    // To I-cache (ufp)
    .mem_req_valid(ic_mem_req_valid),
    .mem_req_addr (ic_mem_req_addr),
    .mem_req_ready(1'b1),          // provided_cache looks always ready here
    .mem_resp_valid(ufp_resp),
    .mem_resp_data (ufp_rdata)
);

// assign icache_req_ready = dem_req_ready;

// drive unified frontend port
assign ufp_addr  = ic_mem_req_addr;
assign ufp_rmask = ic_mem_req_valid ? 4'hF : 4'h0;

if_stage #(.ENABLE_RAS(1)) u_if_stage(
    .clk                (clk),
    .rst                (rst),

    .redirect_valid     (flush_valid),
    .redirect_pc        (redirect_pc),

    .inst_valid         (if_inst_valid),
    .inst               (if_inst),
    .inst_pc            (if_pc),
    .inst_ready         (if_inst_ready),

    .icache_req_valid   (icache_req_valid),
    .icache_req_addr    (icache_req_addr),
    .icache_req_ready   (icache_req_ready),
    .icache_resp_valid  (icache_resp_valid),
    .icache_resp_data   (icache_resp_data),
    .bpred_update_valid (bpred_update_valid),
    .bpred_update_idx   (bpred_update_idx),
    .bpred_update_taken (commit_branch_taken),
    .inst_pred_taken   (if_pred_taken),
    .inst_bht_idx      (if_bht_idx),
    .inst_pred_target   (if_pred_target),
    .btb_update_valid  (btb_update_valid),
    .btb_update_pc     (btb_update_pc),
    .btb_update_target (btb_update_target)
);

// assign icache_resp_valid = dem_resp_valid;
// assign icache_resp_data  = dem_resp_data;

fifo_queue #(16, IQ_WIDTH) inst_queue (
    .clk   (clk),
    .rst   (rst),
    .enq   (fifo_enq),
    .deq   (fifo_deq),
    .d_in  (fifo_d_in),
    .d_out (fifo_d_out),
    .full  (full),
    .empty (empty),
    .flush (flush_valid)
);

logic        cdb_valid, cdb_ready;
logic [31:0] cdb_value;
logic [ARCH_REG_IDX:0] cdb_rd;
logic [PHYS_REG_IDX:0] cdb_pd;
logic [$clog2(NUM_ROB_ENTRIES)-1:0] cdb_rob;
logic        cdb_we;

logic q_ready;
logic                     dec_valid, dec_ready;
logic [ARCH_REG_IDX:0]    dec_rs1, dec_rs2, dec_rd;
logic [31:0]              dec_imm;
logic [3:0]               dec_alu_op;
logic [6:0]               dec_opcode;
logic                     dec_dest_we;
logic [1:0]               dec_fukind;
logic [31:0]              dec_pc;
logic [63:0]              dec_order;
logic [31:0]              dec_inst;
logic [2:0]               dec_subop;
logic dec_pred_taken;
logic [7:0] dec_bht_idx;
logic [31:0] dec_pred_target;

assign fifo_deq   = !empty && q_ready;

logic iq_pred_taken;
logic [7:0] iq_bht_idx;
logic [31:0] iq_inst;
logic [31:0] iq_pc;
logic [31:0] iq_pred_target;

assign {iq_pred_taken, iq_bht_idx, iq_pred_target, iq_pc, iq_inst} = fifo_d_out;

decode id_stage (
  .clk         (clk),
  .rst         (rst),
  .iq_valid    (!empty),
  .iq_pc       (iq_pc),
  .iq_inst     (iq_inst),
  .iq_pred_taken (iq_pred_taken),
  .iq_pred_target (iq_pred_target),
  .iq_bht_idx   (iq_bht_idx),
  .iq_ready    (q_ready),
  .dec_valid   (dec_valid),
  .dec_ready   (dec_ready),
  .dec_rs1     (dec_rs1),
  .dec_rs2     (dec_rs2),
  .dec_rd      (dec_rd),
  .dec_imm     (dec_imm),
  .dec_alu_op  (dec_alu_op),
  .dec_opcode  (dec_opcode),
  .dec_dest_we (dec_dest_we),
  .dec_fukind  (dec_fukind),
  .dec_pc      (dec_pc),
  .dec_order   (dec_order),
  .dec_inst    (dec_inst),
  .dec_subop   (dec_subop),
  .dec_flush   (flush_valid),
  .dec_pred_taken (dec_pred_taken),
  .dec_bht_idx   (dec_bht_idx),
  .dec_pred_target (dec_pred_target)
);

logic                   fl_alloc_req, fl_alloc_gnt;
logic [PHYS_REG_IDX:0]  fl_pd_alloc;
logic                   fl_free_valid;
logic [PHYS_REG_IDX:0]  fl_free_pd;
logic [31:0] fl_head_snapshot;
logic [31:0] fl_tail_snapshot;
logic [31:0] fl_count_snapshot;

logic        fl_restore_valid;
logic [31:0] fl_restore_head;
logic [31:0] fl_restore_tail;
logic [31:0] fl_restore_count;

FreelistFIFO u_freelist (
  .clk         (clk),
  .rst         (rst),
  .alloc_req   (fl_alloc_req),
  .alloc_gnt   (fl_alloc_gnt),
  .pd_alloc    (fl_pd_alloc),
  .free_valid  (fl_free_valid),
  .free_pd     (fl_free_pd),
  .full        (),
  .empty       (),
  .almost_empty(),
  .flush_valid (flush_valid_r)
);

ren_to_rat_req_t rat_req;
rat_to_ren_rsp_t rat_rsp;

cdb_entry_t      rat_cdb_snoop;
logic [PHYS_REG_IDX:0] rrat_table [NUM_ARCH_REG];

RAT #(
  .LOG_REGS(NUM_ARCH_REG),
  .PHY_REGS(NUM_PHYS_REG)
)
u_rat (
  .clk     (clk),
  .rst     (rst),
  .rat_req (rat_req),
  .rat_rsp (rat_rsp),
  .cdb_entry(rat_cdb_snoop),
  .flush_valid(flush_valid_r),
  .rrat_map(rrat_table)
);

logic [31:0] alu_res_val;
logic [ARCH_REG_IDX:0] alu_res_rd;
logic [PHYS_REG_IDX:0] alu_res_pd;
logic [$clog2(NUM_ROB_ENTRIES)-1:0] alu_res_rob;
logic alu_res_we;
logic [31:0] alu_pc, alu_pc_o;
logic [6:0] alu_opcode, alu_opcode_o;
logic [2:0]  alu_funct3, alu_funct3_o;
logic        alu_branch_taken, alu_is_ctrl_inst;
logic [31:0] alu_branch_target;

logic [31:0] mem_pc;
logic [6:0] mem_opcode;

dispatch_to_ROB_t   rtrob;
ROB_to_dispatch_t   rob2dis;
cdb_entry_t         rob_cdb_snoop;

logic [$clog2(NUM_ROB_ENTRIES)-1:0] rob_tail_idx;
wire rob_src_we_mux;
wire [$clog2(NUM_ROB_ENTRIES)-1:0] rob_src_idx_mux;
wire [31:0] rob_src_rs1_mux;
wire [31:0] rob_src_rs2_mux;
logic alu_src_we, mul_src_we, div_src_we;
logic [$clog2(NUM_ROB_ENTRIES)-1:0] alu_src_idx, mul_src_idx, div_src_idx;
logic [31:0] alu_src_rs1, mul_src_rs1, div_src_rs1;
logic [31:0] alu_src_rs2, mul_src_rs2, div_src_rs2;
logic [2:0] mult_subop;
logic [2:0] div_subop;
logic [2:0] mult_subop_fu;
logic [2:0] div_subop_fu;

logic mem_src_we;
logic [$clog2(NUM_ROB_ENTRIES)-1:0] mem_src_idx;
logic [31:0] mem_src_rs1, mem_src_rs2;

logic rob_br_we;
logic [$clog2(NUM_ROB_ENTRIES)-1:0] rob_br_idx;
logic rob_br_taken;
logic [31:0] rob_br_target;
logic [$clog2(NUM_ROB_ENTRIES)-1:0] rob_head_idx;
logic [31:0]   commit_branch_target;

assign rob_src_we_mux   = alu_src_we | mul_src_we | div_src_we | mem_src_we;
assign rob_src_idx_mux  =
    alu_src_we ? alu_src_idx :
    mul_src_we ? mul_src_idx :
    div_src_we ? div_src_idx :
    mem_src_we ? mem_src_idx : '0;
assign rob_src_rs1_mux  =
    alu_src_we ? alu_src_rs1 :
    mul_src_we ? mul_src_rs1 :
    div_src_we ? div_src_rs1 :
    mem_src_we ? mem_src_rs1 : '0;
assign rob_src_rs2_mux  =
    alu_src_we ? alu_src_rs2 :
    mul_src_we ? mul_src_rs2 :
    div_src_we ? div_src_rs2 :
    mem_src_we ? mem_src_rs2 : '0;

logic commit_mispredicted;
assign commit_mispredicted = commit_valid && ((commit_pc + 32'd4) != commit_next_pc);

ROB u_rob (
  .clk            (clk),
  .rst            (rst),
  .rtrob          (rtrob),
  .rob_to_dispatch(rob2dis),
  .cdbrob_rob     (rob_cdb_snoop),
  .rob_to_rrf     (rob_to_rrf),
  .rrf_to_rob     (rrf_to_rob),
  .rob_full       (rob_full), 
  .rob_empty      (rob_empty), 
  .rob_count      (),
  .rob_head_idx   (rob_head_idx), 
  .rob_tail_idx   (rob_tail_idx),
  .commit_valid   (commit_valid),
  .src_sample_we       (rob_src_we_mux),
  .src_sample_idx      (rob_src_idx_mux),
  .src_sample_rs1_val  (rob_src_rs1_mux),
  .src_sample_rs2_val  (rob_src_rs2_mux),
  .br_taken            (commit_mispredicted),
  .br_target           (commit_next_pc),
  .flush_valid         (flush_valid),
  .commit_branch_taken (commit_branch_taken),
  .commit_branch_target(commit_branch_target),
  .bpred_update_valid (bpred_update_valid),
  .bpred_update_idx   (bpred_update_idx),
  .bpred_update_taken (bpred_update_taken)
);

assign rrf_to_rob.dequeue = commit_valid && (!commit_is_store || (pcsb_enq_ready && lsq_commit_ready));

logic                  rrat_free_valid;
logic [PHYS_REG_IDX:0] rrat_free_pd;

RRAT u_rrat (
  .clk         (clk),
  .rst         (rst),
  .commit_valid(commit_valid),
  .commit_uop  (rob_to_rrf.rob_entry),
  .rrat_table  (rrat_table),
  .free_valid  (rrat_free_valid),
  .free_pd     (rrat_free_pd)
);

assign fl_free_valid = rrat_free_valid;
assign fl_free_pd    = rrat_free_pd;

logic [PHYS_REG_IDX:0] prf_rs1_pid_mux, prf_rs2_pid_mux;
logic [31:0]           prf_rs1_rdata, prf_rs2_rdata;
logic                  prf_rs1_ready, prf_rs2_ready;

logic                  prf_alloc_valid;
logic [PHYS_REG_IDX:0] prf_alloc_pid;

assign prf_alloc_valid = fl_alloc_gnt;
assign prf_alloc_pid   = fl_pd_alloc;

prf u_prf (
  .clk        (clk),
  .rst        (rst),
  .rs1_pid    (prf_rs1_pid_mux),
  .rs2_pid    (prf_rs2_pid_mux),
  .rs1_rdata  (prf_rs1_rdata),
  .rs2_rdata  (prf_rs2_rdata),
  .rs1_ready  (prf_rs1_ready),
  .rs2_ready  (prf_rs2_ready),
  .alloc_valid(prf_alloc_valid),
  .alloc_pid  (prf_alloc_pid),
  .free_valid (1'b0),
  .free_pid   ('0),
  .cdb_valid  (cdb_valid & cdb_we),
  .cdb_pid    (cdb_pd),
  .cdb_value  (cdb_value)
);

// ALU RS
logic alu_enq_valid, alu_enq_ready;
logic [PHYS_REG_IDX:0]  alu_ps1, alu_ps2, alu_pd;
logic                   alu_rs1_rdy, alu_rs2_rdy, alu_dest_we;
logic [31:0]            alu_imm;
logic [3:0]             alu_op;
logic [ARCH_REG_IDX:0]  alu_rd;
logic [$clog2(NUM_ROB_ENTRIES)-1:0] alu_rob_idx;

logic alu_issue_valid, alu_issue_ready;
logic alu_fu_ready, mul_fu_ready, div_fu_ready;
logic [PHYS_REG_IDX:0] alu_prf_rs1_pid, alu_prf_rs2_pid;
logic [31:0]           alu_op_a, alu_op_b, alu_op_imm;
logic [3:0]            alu_issue_op;
logic [PHYS_REG_IDX:0] alu_pd_o;
logic [ARCH_REG_IDX:0] alu_rd_o;
logic [$clog2(NUM_ROB_ENTRIES)-1:0] alu_rob_idx_o;
logic alu_dest_we_o;

logic lsu_resp_valid, lsu_resp_ready;
logic lsu_resp_ready_arb;
logic [31:0] lsu_res_val;
logic [ARCH_REG_IDX:0] lsu_res_rd;
logic [PHYS_REG_IDX:0] lsu_res_pd;
logic [$clog2(NUM_ROB_ENTRIES)-1:0] lsu_res_rob;
logic        lsu_res_we;

reservation_station #(.ENTRIES(8)) u_rs_alu (
  .clk        (clk), .rst (rst),
  .enq_valid  (alu_enq_valid),
  .enq_ready  (alu_enq_ready),
  .ps1_i      (alu_ps1), .ps2_i(alu_ps2),
  .rs1_ready_i(alu_rs1_rdy), .rs2_ready_i(alu_rs2_rdy),
  .imm_i      (alu_imm), .alu_op_i(alu_op),
  .pd_i       (alu_pd), .rd_i(alu_rd),
  .rob_i      (alu_rob_idx), .dest_we_i(alu_dest_we),
  .cdb_valid  (rob_cdb_snoop.valid),
  .cdb_pid    (rob_cdb_snoop.pd),
  .cdb_value  (cdb_value),
  .prf_rs1_pid(alu_prf_rs1_pid),
  .prf_rs2_pid(alu_prf_rs2_pid),
  .prf_rs1_rdata(prf_rs1_rdata),
  .prf_rs2_rdata(prf_rs2_rdata),
  .issue_valid(alu_issue_valid),
  .issue_ready(alu_issue_ready),
  .op_a       (alu_op_a),
  .op_b       (alu_op_b),
  .op_imm     (alu_op_imm),
  .alu_op     (alu_issue_op),
  .pd_o       (alu_pd_o),
  .rd_o       (alu_rd_o),
  .rob_o      (alu_rob_idx_o),
  .dest_we_o  (alu_dest_we_o),
  .rob_src_we      (alu_src_we),
  .rob_src_idx     (alu_src_idx),
  .rob_src_rs1_val (alu_src_rs1),
  .rob_src_rs2_val (alu_src_rs2),
  .sub_op_i       (3'b000),
  .sub_op_o       (),
  .pc_i         (alu_pc),
  .opcode_i     (alu_opcode),
  .funct3_i     (alu_funct3),
  .pc_o         (alu_pc_o),
  .opcode_o     (alu_opcode_o),
  .funct3_o     (alu_funct3_o),
  .flush        (flush_valid)
);

// MUL RS
logic mul_enq_valid, mul_enq_ready;
logic [PHYS_REG_IDX:0]  mul_ps1, mul_ps2, mul_pd;
logic                   mul_rs1_rdy, mul_rs2_rdy, mul_dest_we;
logic [ARCH_REG_IDX:0]  mul_rd;
logic [$clog2(NUM_ROB_ENTRIES)-1:0] mul_rob_idx;

logic mul_issue_valid, mul_issue_ready;
logic [PHYS_REG_IDX:0] mul_prf_rs1_pid, mul_prf_rs2_pid;
logic [31:0]           mul_op_a, mul_op_b;
logic [PHYS_REG_IDX:0] mul_pd_o;
logic [ARCH_REG_IDX:0] mul_rd_o;
logic [$clog2(NUM_ROB_ENTRIES)-1:0] mul_rob_idx_o;
logic mul_dest_we_o;

logic [31:0] mul_op_imm;
logic [3:0] mul_alu_op;

reservation_station #(.ENTRIES(4)) u_rs_mul (
  .clk        (clk), .rst (rst),
  .enq_valid  (mul_enq_valid),
  .enq_ready  (mul_enq_ready),
  .ps1_i      (mul_ps1), .ps2_i(mul_ps2),
  .rs1_ready_i(mul_rs1_rdy), .rs2_ready_i(mul_rs2_rdy),
  .imm_i      (32'd0), .alu_op_i(4'd0),
  .pd_i       (mul_pd), .rd_i(mul_rd),
  .rob_i      (mul_rob_idx), .dest_we_i(mul_dest_we),
  .cdb_valid  (rob_cdb_snoop.valid),
  .cdb_pid    (rob_cdb_snoop.pd),
  .cdb_value  (cdb_value),
  .prf_rs1_pid(mul_prf_rs1_pid),
  .prf_rs2_pid(mul_prf_rs2_pid),
  .prf_rs1_rdata(prf_rs1_rdata),
  .prf_rs2_rdata(prf_rs2_rdata),
  .issue_valid(mul_issue_valid),
  .issue_ready(mul_issue_ready),
  .op_a       (mul_op_a),
  .op_b       (mul_op_b),
  .op_imm     (mul_op_imm), 
  .alu_op     (mul_alu_op),
  .funct3_i   ('0),
  .opcode_i   ('0),
  .pd_o       (mul_pd_o),
  .rd_o       (mul_rd_o),
  .rob_o      (mul_rob_idx_o),
  .dest_we_o  (mul_dest_we_o), 
  .rob_src_we      (mul_src_we),
  .rob_src_idx     (mul_src_idx),
  .rob_src_rs1_val (mul_src_rs1),
  .rob_src_rs2_val (mul_src_rs2),
  .sub_op_i       (mult_subop),
  .sub_op_o       (mult_subop_fu),
  .flush        (flush_valid),
  .pc_i         (mem_pc)
);

logic [31:0] unused_mul_op_imm;
logic [3:0] unused_mul_alu_op;
assign unused_mul_op_imm = mul_op_imm;
assign unused_mul_alu_op = mul_alu_op;

// DIV RS
logic div_enq_valid, div_enq_ready;
logic [PHYS_REG_IDX:0]  div_ps1, div_ps2, div_pd;
logic                   div_rs1_rdy, div_rs2_rdy, div_dest_we;
logic [ARCH_REG_IDX:0]  div_rd;
logic [$clog2(NUM_ROB_ENTRIES)-1:0] div_rob_idx;

logic div_issue_valid, div_issue_ready;
logic [PHYS_REG_IDX:0] div_prf_rs1_pid, div_prf_rs2_pid;
logic [31:0]           div_op_a, div_op_b;
logic [PHYS_REG_IDX:0] div_pd_o;
logic [ARCH_REG_IDX:0] div_rd_o;
logic [$clog2(NUM_ROB_ENTRIES)-1:0] div_rob_idx_o;
logic div_dest_we_o;

logic [31:0] div_op_imm;
logic [3:0] div_alu_op;

reservation_station #(.ENTRIES(4)) u_rs_div (
  .clk        (clk), .rst (rst),
  .enq_valid  (div_enq_valid),
  .enq_ready  (div_enq_ready),
  .ps1_i      (div_ps1), .ps2_i(div_ps2),
  .rs1_ready_i(div_rs1_rdy), .rs2_ready_i(div_rs2_rdy),
  .imm_i      (32'd0), .alu_op_i(4'd0),
  .pd_i       (div_pd), .rd_i(div_rd),
  .rob_i      (div_rob_idx), .dest_we_i(div_dest_we),
  .cdb_valid  (rob_cdb_snoop.valid),
  .cdb_pid    (rob_cdb_snoop.pd),
  .cdb_value  (cdb_value),
  .prf_rs1_pid(div_prf_rs1_pid),
  .prf_rs2_pid(div_prf_rs2_pid),
  .prf_rs1_rdata(prf_rs1_rdata),
  .prf_rs2_rdata(prf_rs2_rdata),
  .issue_valid(div_issue_valid),
  .issue_ready(div_issue_ready),
  .op_a       (div_op_a),
  .op_b       (div_op_b),
  .op_imm     (div_op_imm), 
  .alu_op     (div_alu_op),
  .funct3_i   ('0),
  .opcode_i   ('0),
  .pc_i       ('0),
  .pd_o       (div_pd_o),
  .rd_o       (div_rd_o),
  .rob_o      (div_rob_idx_o),
  .dest_we_o  (div_dest_we_o), 
  .rob_src_we      (div_src_we),
  .rob_src_idx     (div_src_idx),
  .rob_src_rs1_val (div_src_rs1),
  .rob_src_rs2_val (div_src_rs2),
  .sub_op_i       (div_subop),
  .sub_op_o       (div_subop_fu),
  .flush        (flush_valid)
);

logic [31:0] unused_div_op_imm;
logic [3:0] unused_div_alu_op;
assign unused_div_op_imm = div_op_imm;
assign unused_div_alu_op = div_alu_op;

logic        mem_enq_valid, mem_enq_ready;
logic [PHYS_REG_IDX:0]  mem_ps1, mem_ps2, mem_pd;
logic                   mem_rs1_rdy, mem_rs2_rdy, mem_dest_we;
logic [31:0]            mem_imm, mem_op_a, mem_op_b, mem_op_imm;
logic [2:0]             mem_funct3;
logic [ARCH_REG_IDX:0]  mem_rd;
logic [$clog2(NUM_ROB_ENTRIES)-1:0] mem_rob_idx;

logic mem_issue_valid, mem_issue_ready;
logic [PHYS_REG_IDX:0] mem_prf_rs1_pid, mem_prf_rs2_pid;
logic [PHYS_REG_IDX:0] mem_pd_o;
logic [ARCH_REG_IDX:0] mem_rd_o;
logic [$clog2(NUM_ROB_ENTRIES)-1:0] mem_rob_idx_o;
logic mem_dest_we_o;
logic [31:0] mem_store_data;
logic [3:0]  mem_issue_op;
wire  [2:0]  mem_issue_funct3 = mem_issue_op[2:0];
wire         issue_is_store   = ~mem_dest_we_o;

assign mem_store_data = mem_op_b;

reservation_station #(.ENTRIES(4), .FORCE_IN_ORDER(1'b1)) u_rs_mem (
  .clk        (clk), 
  .rst        (rst),
  .enq_valid  (mem_enq_valid),
  .enq_ready  (mem_enq_ready),
  .ps1_i      (mem_ps1), 
  .ps2_i      (mem_ps2),
  .rs1_ready_i(mem_rs1_rdy), 
  .rs2_ready_i(mem_rs2_rdy),
  .imm_i      (mem_imm),
  .alu_op_i   ({1'b0,mem_funct3}),
  .pd_i       (mem_pd), 
  .rd_i       (mem_rd),
  .rob_i      (mem_rob_idx), 
  .dest_we_i  (mem_dest_we),
  .cdb_valid  (rob_cdb_snoop.valid),
  .cdb_pid    (rob_cdb_snoop.pd),
  .cdb_value  (cdb_value),
  .prf_rs1_pid(mem_prf_rs1_pid),
  .prf_rs2_pid(mem_prf_rs2_pid),
  .prf_rs1_rdata(prf_rs1_rdata),
  .prf_rs2_rdata(prf_rs2_rdata),
  .issue_valid(mem_issue_valid),
  .issue_ready(mem_issue_ready),
  .op_a       (mem_op_a),
  .op_b       (mem_op_b),
  .op_imm     (mem_op_imm),
  .alu_op     (mem_issue_op),
  .pd_o       (mem_pd_o),
  .rd_o       (mem_rd_o),
  .rob_o      (mem_rob_idx_o),
  .dest_we_o  (mem_dest_we_o),
  .rob_src_we      (mem_src_we),
  .rob_src_idx     (mem_src_idx),
  .rob_src_rs1_val (mem_src_rs1),
  .rob_src_rs2_val (mem_src_rs2),
  .sub_op_i        (mem_funct3),
  .sub_op_o        (),
  .flush           (flush_valid),
  .pc_i            (mem_pc),
  .opcode_i       (mem_opcode),
  .funct3_i       (mem_funct3),
  .pc_o           (),
  .opcode_o       (),
  .funct3_o       ()
);

wire rs_has_space =
  (dec_fukind==2'd0) ? alu_enq_ready :
  (dec_fukind==2'd1) ? mul_enq_ready :
  (dec_fukind==2'd2) ? div_enq_ready : 
  (dec_fukind==2'd3) ? mem_enq_ready : 1'b0;

assign fl_alloc_req =
  dec_valid && dec_dest_we && (dec_rd != '0) && rs_has_space && !rob_full;

typedef enum logic [2:0] {SEL_NONE, SEL_ALU, SEL_MUL, SEL_DIV, SEL_MEM} iss_sel_e;
iss_sel_e iss_sel;

localparam ROBW = $clog2(NUM_ROB_ENTRIES);
logic sg_alloc_store_valid;
logic [ROBW-1:0] sg_alloc_store_rob_idx;
logic sg_enq_store_fire;
logic [ROBW-1:0] sg_enq_store_rob_idx;
logic [ROBW-1:0] lsq_cand_rob_idx;
logic cand_has_older_store_unknown;

assign sg_alloc_store_valid = mem_enq_valid && mem_enq_ready && ~mem_dest_we;
assign sg_alloc_store_rob_idx = mem_rob_idx;
assign sg_enq_store_fire = (mem_issue_valid && (iss_sel == SEL_MEM) && lsq_enq_ready && issue_is_store);
assign sg_enq_store_rob_idx = mem_rob_idx_o;

logic can_alu, can_mul, can_div, can_mem;
logic mem_head_prio;
assign can_alu = alu_issue_valid && alu_fu_ready;
assign can_mul = mul_issue_valid && mul_fu_ready;
assign can_div = div_issue_valid && div_fu_ready;
assign can_mem = mem_issue_valid && lsq_enq_ready;
assign mem_head_prio = can_mem && (mem_rob_idx_o == rob_head_idx);

always_comb begin
  iss_sel = SEL_NONE;
  if (mem_head_prio) iss_sel = SEL_MEM;
  else if (can_alu)      iss_sel = SEL_ALU;
  else if (can_mul) iss_sel = SEL_MUL;
  else if (can_div) iss_sel = SEL_DIV;
  else if (can_mem) iss_sel = SEL_MEM;

  unique case (iss_sel)
    SEL_ALU: begin prf_rs1_pid_mux = alu_prf_rs1_pid; prf_rs2_pid_mux = alu_prf_rs2_pid; end
    SEL_MUL: begin prf_rs1_pid_mux = mul_prf_rs1_pid; prf_rs2_pid_mux = mul_prf_rs2_pid; end
    SEL_DIV: begin prf_rs1_pid_mux = div_prf_rs1_pid; prf_rs2_pid_mux = div_prf_rs2_pid; end
    SEL_MEM: begin prf_rs1_pid_mux = mem_prf_rs1_pid; prf_rs2_pid_mux = mem_prf_rs2_pid; end
    default: begin prf_rs1_pid_mux = '0; prf_rs2_pid_mux = '0; end
  endcase
end

assign alu_issue_ready = (iss_sel == SEL_ALU) && alu_fu_ready;
assign mul_issue_ready = (iss_sel == SEL_MUL) && mul_fu_ready;
assign div_issue_ready = (iss_sel == SEL_DIV) && div_fu_ready;
assign mem_issue_ready = (iss_sel == SEL_MEM) && lsq_enq_ready;

logic alu_resp_valid, mul_resp_valid, div_resp_valid;
logic alu_resp_ready, mul_resp_ready, div_resp_ready;

logic cdb_is_ctrl;
logic cdb_br_taken;
logic [31:0] cdb_br_target;
logic [6:0] cdb_opcode;
logic [31:0] cdb_pc;

assign redirect_valid = mispredict;
assign flush_valid    = mispredict;
assign redirect_pc    = commit_next_pc;

assign rob_br_we      = cdb_valid && cdb_is_ctrl;
assign rob_br_idx     = cdb_rob;
assign rob_br_taken   = cdb_br_taken;
assign rob_br_target  = cdb_br_target;

alu u_alu (
  .clk(clk), .rst(rst),
  .req_valid (alu_issue_valid && (iss_sel==SEL_ALU)),
  .req_ready (alu_fu_ready),
  .op_a      (alu_op_a),
  .op_b      (alu_op_b),
  .op_imm    (alu_op_imm),
  .alu_op    (alu_issue_op),
  .rd_arch   (alu_rd_o),
  .pd_phys   (alu_pd_o),
  .rob_idx   (alu_rob_idx_o),
  .dest_we   (alu_dest_we_o),
  .resp_valid(alu_resp_valid),
  .resp_ready(alu_resp_ready),
  .resp_value(alu_res_val),
  .resp_rd   (alu_res_rd),
  .resp_pd   (alu_res_pd),
  .resp_rob_idx(alu_res_rob),
  .resp_dest_we(alu_res_we),
  .pc        (alu_pc_o),
  .opcode    (alu_opcode_o),
  .funct3    (alu_funct3_o),
  .br_taken  (alu_branch_taken),
  .br_target (alu_branch_target),
  .is_ctrl_inst(alu_is_ctrl_inst),
  .is_branch_mod   (is_branch),
  .is_jalr_mod    (is_jalr)
);

logic [31:0] mul_res_val; logic [ARCH_REG_IDX:0] mul_res_rd; logic [PHYS_REG_IDX:0] mul_res_pd;
logic [$clog2(NUM_ROB_ENTRIES)-1:0] mul_res_rob; logic mul_res_we;

mul u_mul (
  .clk         (clk),
  .rst         (rst),

  .req_valid   (mul_issue_valid && (iss_sel == SEL_MUL)),
  .req_ready   (mul_fu_ready),
  .op_a        (mul_op_a),
  .op_b        (mul_op_b),
  .rd_arch     (mul_rd_o),
  .pd_phys     (mul_pd_o),
  .rob_idx     (mul_rob_idx_o),
  .dest_we     (mul_dest_we_o),

  .resp_valid  (mul_resp_valid),
  .resp_ready  (mul_resp_ready),
  .resp_value  (mul_res_val),
  .resp_rd     (mul_res_rd),
  .resp_pd     (mul_res_pd),
  .resp_rob_idx(mul_res_rob),
  .resp_dest_we(mul_res_we),
  .sub_op      (mult_subop_fu)
);

logic [31:0] div_res_val; logic [ARCH_REG_IDX:0] div_res_rd; logic [PHYS_REG_IDX:0] div_res_pd;
logic [$clog2(NUM_ROB_ENTRIES)-1:0] div_res_rob; logic div_res_we;

div u_div (
  .clk         (clk),
  .rst         (rst),

  .req_valid   (div_issue_valid && (iss_sel == SEL_DIV)),
  .req_ready   (div_fu_ready),
  .op_a        (div_op_a),
  .op_b        (div_op_b),
  .rd_arch     (div_rd_o),
  .pd_phys     (div_pd_o),
  .rob_idx     (div_rob_idx_o),
  .dest_we     (div_dest_we_o),

  .resp_valid  (div_resp_valid),
  .resp_ready  (div_resp_ready),
  .resp_value  (div_res_val),
  .resp_rd     (div_res_rd),
  .resp_pd     (div_res_pd),
  .resp_rob_idx(div_res_rob),
  .resp_dest_we(div_res_we),
  .sub_op      (div_subop_fu)
);

assign commit_is_load = commit_valid && (rob_to_rrf.rob_entry.opcode == 7'b0000011);
assign commit_is_store = commit_valid && (rob_to_rrf.rob_entry.opcode == 7'b0100011);
assign f3 = rob_to_rrf.rob_entry.inst[14:12];
assign i_imm_commit = {{21{rob_to_rrf.rob_entry.inst[31]}}, rob_to_rrf.rob_entry.inst[30:20]};
assign load_ea = rob_to_rrf.rob_entry.rs1_value + i_imm_commit;
reg [3:0] ld_mask;

always_comb begin
  unique case (f3)
    3'b000, 3'b100: ld_mask = 4'b0001 << load_ea[1:0];
    3'b001, 3'b101: ld_mask = load_ea[1] ? 4'b1100 : 4'b0011;
    3'b010:         ld_mask = 4'b1111;
    default:        ld_mask = 4'b0000;
  endcase
end

reg [31:0] ld_rdata;
always_comb begin
  ld_rdata = 32'b0;
  unique case (f3)
    3'b000, 3'b100: begin
      case (load_ea[1:0])
        2'b00: ld_rdata = {24'b0, rob_to_rrf.rob_entry.value[7:0]};
        2'b01: ld_rdata = {16'b0, rob_to_rrf.rob_entry.value[7:0], 8'b0};
        2'b10: ld_rdata = {8'b0, rob_to_rrf.rob_entry.value[7:0], 16'b0};
        2'b11: ld_rdata = {rob_to_rrf.rob_entry.value[7:0], 24'b0};
      endcase
    end
    3'b001, 3'b101: begin
      ld_rdata = load_ea[1] ? {rob_to_rrf.rob_entry.value[15:0], 16'b0} : {16'b0, rob_to_rrf.rob_entry.value[15:0]};
    end
    3'b010: begin
      ld_rdata = rob_to_rrf.rob_entry.value;
    end
    default: ;
  endcase
end

assign s_imm_commit = {{20{rob_to_rrf.rob_entry.inst[31]}}, rob_to_rrf.rob_entry.inst[31:25], rob_to_rrf.rob_entry.inst[11:7]};
assign store_ea = rob_to_rrf.rob_entry.rs1_value + s_imm_commit;

reg [3:0] st_mask;
reg [31:0] st_wdata;
always_comb begin
  st_mask  = 4'b0000;
  st_wdata = 32'b0;
  unique case (f3)
    3'b000: begin
      st_mask = 4'b0001 << store_ea[1:0];
      unique case (store_ea[1:0])
        2'b00: st_wdata = {24'b0, rob_to_rrf.rob_entry.rs2_value[7:0]};
        2'b01: st_wdata = {16'b0, rob_to_rrf.rob_entry.rs2_value[7:0], 8'b0};
        2'b10: st_wdata = { 8'b0, rob_to_rrf.rob_entry.rs2_value[7:0], 16'b0};
        2'b11: st_wdata = {       rob_to_rrf.rob_entry.rs2_value[7:0], 24'b0};
      endcase
    end
    3'b001: begin
      st_mask  = store_ea[1] ? 4'b1100 : 4'b0011;
      st_wdata = store_ea[1]
               ? {rob_to_rrf.rob_entry.rs2_value[15:0], 16'b0}
               : {16'b0, rob_to_rrf.rob_entry.rs2_value[15:0]};
    end
    3'b010: begin
      st_mask  = 4'b1111;
      st_wdata = rob_to_rrf.rob_entry.rs2_value;
    end
    default: ;
  endcase
end

assign lsu_resp_ready = flush_valid ? 1'b1 : lsu_resp_ready_arb;
wire mem_issue_fire = mem_issue_valid && mem_issue_ready;

// ============================================================================
// PCSB INSTANTIATION
// ============================================================================
assign pcsb_enq_valid = commit_is_store && commit_valid /*&& pcsb_enq_ready && lsq_commit_ready*/;
assign pcsb_enq_addr  = store_ea;
assign pcsb_enq_wmask = st_mask;
assign pcsb_enq_wdata = st_wdata;

pcsb #(.ENTRIES(8)) u_pcsb (
  .clk            (clk),
  .rst            (rst),
  // .flush          (flush_valid),
  .enq_valid      (pcsb_enq_valid),
  .enq_ready      (pcsb_enq_ready),
  .enq_addr       (pcsb_enq_addr),
  .enq_wmask      (pcsb_enq_wmask),
  .enq_wdata      (pcsb_enq_wdata),
  .drain_addr     (pcsb_drain_addr),
  .drain_wmask    (pcsb_drain_wmask),
  .drain_wdata    (pcsb_drain_wdata),
  .drain_valid    (pcsb_drain_valid),
  .drain_ready    (pcsb_drain_ready),
  .drain_resp     (pcsb_drain_resp),
  .fwd_addr       (pcsb_fwd_addr),
  .fwd_rmask      (pcsb_fwd_rmask),
  .fwd_full_hit   (pcsb_fwd_full_hit),
  .fwd_partial    (pcsb_fwd_partial),
  .fwd_data       (pcsb_fwd_data),
  .buf_empty      (pcsb_empty),
  .buf_full       (pcsb_full)
);

// ============================================================================
// D-CACHE ARBITER (LSQ loads vs PCSB drains)
// ============================================================================
always_comb begin
  dcache_owner_d = dcache_owner_q;
  dcache_busy_d  = dcache_busy_q;

  dcache_lsq_resp  = (dcache_owner_q == ARB_LSQ)  ? dcache_resp : 1'b0;
  dcache_pcsb_resp = 1'b0;
  pcsb_drain_resp  = 1'b0;
  pcsb_drain_ready = 1'b0;

  dcache_req_addr = lsq_dcache_addr;
  dcache_rmask    = 4'b0000;
  dcache_wmask    = 4'b0000;
  dcache_wdata    = 32'h0;

  if (!dcache_busy_q) begin
    if (pcsb_drain_valid) begin
      dcache_owner_d   = ARB_PCSB;
      dcache_busy_d    = 1'b1;
      pcsb_drain_ready = 1'b1;
      dcache_req_addr  = pcsb_drain_addr;
      dcache_wmask     = pcsb_drain_wmask;
      dcache_wdata     = pcsb_drain_wdata;
    end else if (lsq_dcache_rmask != 4'b0000) begin
      dcache_owner_d  = ARB_LSQ;
      dcache_busy_d   = 1'b1;
      dcache_req_addr = lsq_dcache_addr;
      dcache_rmask    = lsq_dcache_rmask;
    end
  end else begin
    if (dcache_owner_q == ARB_LSQ) begin
      dcache_req_addr = lsq_dcache_addr;
      dcache_rmask    = lsq_dcache_rmask;
    end else begin
      dcache_req_addr = pcsb_drain_addr;
      dcache_wmask    = pcsb_drain_wmask;
      dcache_wdata    = pcsb_drain_wdata;
    end
  end

  if (dcache_owner_q == ARB_PCSB) dcache_pcsb_resp = dcache_resp;
  else if (!dcache_busy_q && dcache_owner_d == ARB_PCSB) dcache_pcsb_resp = dcache_resp;
  pcsb_drain_resp = dcache_pcsb_resp;

  if (dcache_resp) begin
    dcache_busy_d = 1'b0;
  end
end

always_ff @(posedge clk) begin
  if (rst) begin
    dcache_owner_q <= ARB_LSQ;
    dcache_busy_q  <= 1'b0;
  end else begin
    dcache_owner_q <= dcache_owner_d;
    dcache_busy_q  <= dcache_busy_d;
  end
end

// ============================================================================
// LSQ INSTANTIATION (with PCSB forwarding)
// ============================================================================
lsq u_lsq (
  .clk                 (clk),
  .rst                 (rst),
  .enq_valid           (mem_issue_valid && (iss_sel == SEL_MEM)),
  .enq_ready           (lsq_enq_ready),
  .is_store            (issue_is_store),
  .base_addr           (mem_op_a),
  .offset              (mem_op_imm),
  .store_data          (mem_store_data),
  .funct3              (mem_issue_funct3),
  .rob_idx             (mem_rob_idx_o),
  .pd                  (mem_pd_o),
  .rd                  (mem_rd_o),
  .dcache_addr         (lsq_dcache_addr),
  .dcache_rmask        (lsq_dcache_rmask),
  .dcache_wmask        (lsq_dcache_wmask),
  .dcache_wdata        (lsq_dcache_wdata),
  .dcache_rdata        (dcache_rdata),
  .dcache_resp         (dcache_lsq_resp),
  .resp_valid          (lsu_resp_valid),
  .resp_ready          (lsu_resp_ready),
  .resp_value          (lsu_res_val),
  .resp_rd             (lsu_res_rd),
  .resp_pd             (lsu_res_pd),
  .resp_rob_idx        (lsu_res_rob),
  .resp_dest_we        (lsu_res_we),
  .commit_store_valid  (commit_is_store),
  .commit_store_rob_idx(rob_head_idx),
  .commit_store_addr   (store_ea),
  .commit_store_wmask  (st_mask),
  .commit_store_wdata  (st_wdata),
  .commit_store_ready  (lsq_commit_ready),
  .pcsb_fwd_addr       (pcsb_fwd_addr),
  .pcsb_fwd_rmask      (pcsb_fwd_rmask),
  .pcsb_fwd_full_hit   (pcsb_fwd_full_hit),
  .pcsb_fwd_partial    (pcsb_fwd_partial),
  .pcsb_fwd_data       (pcsb_fwd_data),
  .flush               (flush_valid),
  .cand_rob_idx        (lsq_cand_rob_idx),
  .cand_has_older_store_unknown(cand_has_older_store_unknown)
);


logic commit_store_valid;
assign commit_store_valid = commit_valid && commit_is_store;
logic [ROBW-1:0] commit_store_rob_idx;
assign commit_store_rob_idx = rob_head_idx;

store_guard #(
  .NUM_ROB_ENTRIES(NUM_ROB_ENTRIES)
) u_store_guard (
  .clk                         (clk),
  .rst                         (rst),
  .flush                       (flush_valid),
  .rob_head_idx                (rob_head_idx),
  .alloc_store_valid           (sg_alloc_store_valid),
  .alloc_store_rob_idx         (sg_alloc_store_rob_idx),
  .commit_store_valid          (commit_store_valid),
  .commit_store_rob_idx        (commit_store_rob_idx),
  .cand_rob_idx                (lsq_cand_rob_idx),
  .cand_has_older_store_unknown(cand_has_older_store_unknown)
);

// CDB arbiter
localparam integer CDB_PD_BITS  = 10;
localparam integer CDB_ROB_BITS = 6;

wire [CDB_PD_BITS-1:0]  alu_pd_w  = {{(CDB_PD_BITS-$bits(alu_res_pd)){1'b0}}, alu_res_pd};
wire [CDB_ROB_BITS-1:0] alu_rob_w = {{(CDB_ROB_BITS-$bits(alu_res_rob)){1'b0}}, alu_res_rob};
wire [CDB_PD_BITS-1:0]  mul_pd_w  = {{(CDB_PD_BITS-$bits(mul_res_pd)){1'b0}}, mul_res_pd};
wire [CDB_ROB_BITS-1:0] mul_rob_w = {{(CDB_ROB_BITS-$bits(mul_res_rob)){1'b0}}, mul_res_rob};
wire [CDB_PD_BITS-1:0]  div_pd_w  = {{(CDB_PD_BITS-$bits(div_res_pd)){1'b0}}, div_res_pd};
wire [CDB_ROB_BITS-1:0] div_rob_w = {{(CDB_ROB_BITS-$bits(div_res_rob)){1'b0}}, div_res_rob};
wire [CDB_PD_BITS-1:0]  lsu_pd_w  = {{(CDB_PD_BITS-$bits(lsu_res_pd)){1'b0}}, lsu_res_pd};
wire [CDB_ROB_BITS-1:0] lsu_rob_w = {{(CDB_ROB_BITS-$bits(lsu_res_rob)){1'b0}}, lsu_res_rob};

wire [CDB_PD_BITS-1:0]  cdb_pd_w;
wire [CDB_ROB_BITS-1:0] cdb_rob_w;

cdb_arbiter u_cdb (
  .clk(clk), .rst(rst),
  .v0(alu_resp_valid), .r0(alu_resp_ready),
  .val0(alu_res_val), .rd0(alu_res_rd), .pd0(alu_pd_w), .rob0(alu_rob_w), .we0(alu_res_we),
  .v1(mul_resp_valid), .r1(mul_resp_ready),
  .val1(mul_res_val), .rd1(mul_res_rd), .pd1(mul_pd_w), .rob1(mul_rob_w), .we1(mul_res_we),
  .v2(div_resp_valid), .r2(div_resp_ready),
  .val2(div_res_val), .rd2(div_res_rd), .pd2(div_pd_w), .rob2(div_rob_w), .we2(div_res_we),
  .v3(lsu_resp_valid), .r3(lsu_resp_ready_arb),
  .val3(lsu_res_val), .rd3(lsu_res_rd), .pd3(lsu_pd_w), .rob3(lsu_rob_w), .we3(lsu_res_we),
  .cdb_valid(cdb_valid), .cdb_ready(1'b1),
  .cdb_value(cdb_value), .cdb_rd(cdb_rd), .cdb_pd(cdb_pd_w), .cdb_rob(cdb_rob_w), .cdb_we(cdb_we),
  .is_ctrl0(alu_is_ctrl_inst), .br_taken0(alu_branch_taken),.br_target0(alu_branch_target), .opcode0(alu_opcode_o), .pc0(alu_pc_o),
  .cdb_is_ctrl(cdb_is_ctrl), .cdb_br_taken(cdb_br_taken), .cdb_br_target(cdb_br_target), .cdb_opcode(cdb_opcode), .cdb_pc(cdb_pc)
);

assign cdb_pd  = cdb_pd_w[PHYS_REG_IDX:0];
assign cdb_rob = cdb_rob_w[$clog2(NUM_ROB_ENTRIES)-1:0];

assign rat_cdb_snoop.valid         = cdb_valid & cdb_we;
assign rat_cdb_snoop.pd            = cdb_pd;
assign rat_cdb_snoop.rd            = cdb_rd;
assign rat_cdb_snoop.rob_entry_idx = cdb_rob;
assign rat_cdb_snoop.value         = cdb_value;
assign rat_cdb_snoop.rs1_value     = '0;
assign rat_cdb_snoop.rs2_value     = '0;
assign rat_cdb_snoop.opcode        = 7'd0;
assign rat_cdb_snoop.pc            = 32'd0;
assign rat_cdb_snoop.exc           = 1'b0;
assign rat_cdb_snoop.is_ctrl       = cdb_is_ctrl;
assign rat_cdb_snoop.br_taken      = cdb_br_taken;
assign rat_cdb_snoop.br_target     = cdb_br_target;

assign rob_cdb_snoop.valid         = cdb_valid & cdb_we;
assign rob_cdb_snoop.pd            = cdb_pd;
assign rob_cdb_snoop.rd            = cdb_rd;
assign rob_cdb_snoop.rob_entry_idx = cdb_rob;
assign rob_cdb_snoop.value         = cdb_value;
assign rob_cdb_snoop.rs1_value     = '0;
assign rob_cdb_snoop.rs2_value     = '0;
assign rob_cdb_snoop.opcode        = 7'd0;
assign rob_cdb_snoop.pc            = 32'd0;
assign rob_cdb_snoop.exc           = 1'b0;
assign rob_cdb_snoop.is_ctrl       = cdb_is_ctrl;
assign rob_cdb_snoop.br_taken      = cdb_br_taken;
assign rob_cdb_snoop.br_target     = cdb_br_target;

dispatch #(.XLEN(32)) u_dispatch (
  .dec_valid  (dec_valid),
  .dec_ready  (dec_ready),
  .dec_rs1    (dec_rs1),
  .dec_rs2    (dec_rs2),
  .dec_rd     (dec_rd),
  .dec_imm    (dec_imm),
  .dec_alu_op (dec_alu_op),
  .dec_opcode (dec_opcode),
  .dec_dest_we(dec_dest_we),
  .dec_fukind (dec_fukind),
  .dec_pc     (dec_pc),
  .dec_order  (dec_order),
  .dec_inst   (dec_inst),
  .dec_subop  (dec_subop),
  .mult_subop (mult_subop),
  .div_subop  (div_subop),
  .fl_alloc_gnt (fl_alloc_gnt),
  .fl_pd_alloc  (fl_pd_alloc),
  .rat_req    (rat_req),
  .rat_rsp    (rat_rsp),
  .rtrob      (rtrob),
  .rob2dis    (rob2dis),
  .alu_enq_valid(alu_enq_valid),
  .alu_enq_ready(alu_enq_ready),
  .alu_ps1      (alu_ps1),
  .alu_ps2      (alu_ps2),
  .alu_rs1_rdy  (alu_rs1_rdy),
  .alu_rs2_rdy  (alu_rs2_rdy),
  .alu_imm      (alu_imm),
  .alu_op       (alu_op),
  .alu_pd       (alu_pd),
  .alu_rd       (alu_rd),
  .alu_rob_idx  (alu_rob_idx),
  .alu_dest_we  (alu_dest_we),
  .mul_enq_valid(mul_enq_valid),
  .mul_enq_ready(mul_enq_ready),
  .mul_ps1      (mul_ps1),
  .mul_ps2      (mul_ps2),
  .mul_rs1_rdy  (mul_rs1_rdy),
  .mul_rs2_rdy  (mul_rs2_rdy),
  .mul_pd       (mul_pd),
  .mul_rd       (mul_rd),
  .mul_rob_idx  (mul_rob_idx),
  .mul_dest_we  (mul_dest_we),
  .div_enq_valid(div_enq_valid),
  .div_enq_ready(div_enq_ready),
  .div_ps1      (div_ps1),
  .div_ps2      (div_ps2),
  .div_rs1_rdy  (div_rs1_rdy),
  .div_rs2_rdy  (div_rs2_rdy),
  .div_pd       (div_pd),
  .div_rd       (div_rd),
  .div_rob_idx  (div_rob_idx),
  .div_dest_we  (div_dest_we),
  .alu_pc      (alu_pc),
  .alu_opcode  (alu_opcode),
  .alu_funct3  (alu_funct3),
  .mem_pc      (mem_pc),
  .mem_opcode  (mem_opcode),
  .mem_funct3  (mem_funct3),
  .mem_enq_valid(mem_enq_valid),
  .mem_enq_ready(mem_enq_ready),
  .mem_ps1      (mem_ps1),
  .mem_ps2      (mem_ps2),
  .mem_rs1_rdy  (mem_rs1_rdy),
  .mem_rs2_rdy  (mem_rs2_rdy),
  .mem_imm      (mem_imm),
  .mem_pd       (mem_pd),
  .mem_rd       (mem_rd),
  .mem_rob_idx  (mem_rob_idx),
  .mem_dest_we  (mem_dest_we),
  .dec_pred_taken (dec_pred_taken),
  .dec_pred_target (dec_pred_target),
  .dec_bht_idx   (dec_bht_idx)
);

always_ff @(posedge clk) begin
  if (rst) begin
    flush_valid_r <= 1'b0;
  end else begin
    flush_valid_r <= flush_valid;
  end
end

// RVFI bus
localparam integer RVFI_CH = 1;

logic                rvfi_valid   [RVFI_CH];
logic [63:0]         rvfi_order   [RVFI_CH];
logic [31:0]         rvfi_inst    [RVFI_CH];
logic [4:0]          rvfi_rs1_addr[RVFI_CH];
logic [4:0]          rvfi_rs2_addr[RVFI_CH];
logic [31:0]         rvfi_rs1_rdata[RVFI_CH];
logic [31:0]         rvfi_rs2_rdata[RVFI_CH];
logic [4:0]          rvfi_rd_addr [RVFI_CH];
logic [31:0]         rvfi_rd_wdata[RVFI_CH];
logic [31:0]         rvfi_pc_rdata[RVFI_CH];
logic [31:0]         rvfi_pc_wdata[RVFI_CH];
logic [31:0]         rvfi_mem_addr[RVFI_CH];
logic [3:0]          rvfi_mem_rmask[RVFI_CH];
logic [3:0]          rvfi_mem_wmask[RVFI_CH];
logic [31:0]         rvfi_mem_rdata[RVFI_CH];
logic [31:0]         rvfi_mem_wdata[RVFI_CH];

logic [63:0] rvfi_order_ctr_q, rvfi_order_ctr_d;

always_comb begin
  rvfi_order_ctr_d = rvfi_order_ctr_q;
  if (commit_valid && rrf_to_rob.dequeue)
    rvfi_order_ctr_d = rvfi_order_ctr_q + 64'd1;
end

always_ff @(posedge clk) begin
  if (rst) begin
    rvfi_order_ctr_q <= 64'd0;
  end else begin
    rvfi_order_ctr_q <= rvfi_order_ctr_d;
  end
end

logic [63:0] branch_count;
logic [63:0] mispredict_count;

always_ff @(posedge clk) begin
  if (rst) begin
    branch_count <= 64'd0;
  end else if (commit_valid && commit_branch_taken && rrf_to_rob.dequeue) begin
    branch_count <= branch_count + 64'd1;
  end
end

logic [63:0] cf_count;  // control-flow instruction count

always_ff @(posedge clk) begin
  if (rst) begin
    cf_count <= 64'd0;
  end else if (commit_valid && rrf_to_rob.dequeue) begin
    if (commit_is_branch || commit_is_jal || commit_is_jalr) begin
      cf_count <= cf_count + 64'd1;
    end
  end
end

always_ff @(posedge clk) begin
  if (rst) begin
    mispredict_count <= 64'd0;
  end else if (mispredict) begin
    mispredict_count <= mispredict_count + 64'd1;
  end
end

assign rvfi_valid[0]     = rrf_to_rob.dequeue;
assign rvfi_order[0]     = rvfi_order_ctr_q;
assign rvfi_inst[0] = rrf_to_rob.dequeue ? rob_to_rrf.rob_entry.inst : 32'd0;

assign rvfi_rs1_addr[0]  = commit_valid && rob_to_rrf.rob_entry.uses_rs1 ? rob_to_rrf.rob_entry.rs1 : 5'd0;
assign rvfi_rs2_addr[0]  = commit_valid && rob_to_rrf.rob_entry.uses_rs2 ? rob_to_rrf.rob_entry.rs2 : 5'd0;
assign rvfi_rs1_rdata[0] = commit_valid && rob_to_rrf.rob_entry.uses_rs1 ? rob_to_rrf.rob_entry.rs1_value : 32'd0;
assign rvfi_rs2_rdata[0] = commit_valid && rob_to_rrf.rob_entry.uses_rs2 ? rob_to_rrf.rob_entry.rs2_value : 32'd0;

assign rvfi_rd_addr[0]   = commit_valid ? rob_to_rrf.rob_entry.rd    : 5'd0;
assign rvfi_rd_wdata[0]  = (commit_valid && rob_to_rrf.rob_entry.dest_we && (rob_to_rrf.rob_entry.rd != 5'd0)) ? rob_to_rrf.rob_entry.value : 32'd0;
assign rvfi_pc_rdata[0]  = commit_valid ? rob_to_rrf.rob_entry.pc    : 32'd0;
assign rvfi_pc_wdata[0]  = commit_valid ? commit_next_pc : 32'd0;

assign rvfi_mem_addr[0]  = commit_is_store ? store_ea : commit_is_load ? load_ea : 32'b0;
assign rvfi_mem_rmask[0] = commit_is_load ? ld_mask : 4'b0000;
assign rvfi_mem_wmask[0] = commit_is_store ? st_mask : 4'b0000;
assign rvfi_mem_rdata[0] = commit_is_load ? ld_rdata : 32'b0;
assign rvfi_mem_wdata[0] = commit_is_store ? st_wdata : 32'b0;

endmodule : cpu