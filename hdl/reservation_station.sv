module reservation_station
import rv32i_types::*; #(
  parameter integer XLEN    = 32,
  parameter integer ENTRIES = 8,
  parameter logic   FORCE_IN_ORDER = 1'b0
)(
  input  logic clk,
  input  logic rst,

  // Enqueue from Dispatch
  input  logic                                    enq_valid,
  output logic                                    enq_ready,
  input  logic [rv32i_types::PHYS_REG_IDX:0]      ps1_i,
  input  logic [rv32i_types::PHYS_REG_IDX:0]      ps2_i,
  input  logic                                    rs1_ready_i,
  input  logic                                    rs2_ready_i,
  input  logic [XLEN-1:0]                         imm_i,
  input  logic [3:0]                              alu_op_i,
  input  logic [rv32i_types::PHYS_REG_IDX:0]      pd_i,
  input  logic [rv32i_types::ARCH_REG_IDX:0]      rd_i,
  input  logic [$clog2(rv32i_types::NUM_ROB_ENTRIES)-1:0] rob_i,
  input  logic                                    dest_we_i,

  // CDB snoop
  input  logic                                    cdb_valid,
  input  logic [rv32i_types::PHYS_REG_IDX:0]      cdb_pid,
  input logic [XLEN-1:0] cdb_value,

  // PRF read for selected entry
  output logic [rv32i_types::PHYS_REG_IDX:0]      prf_rs1_pid,
  output logic [rv32i_types::PHYS_REG_IDX:0]      prf_rs2_pid,
  input  logic [XLEN-1:0]                         prf_rs1_rdata,
  input  logic [XLEN-1:0]                         prf_rs2_rdata,

  // Issue to ALU/MUL/DIV
  output logic                                    issue_valid,
  input  logic                                    issue_ready,
  output logic [XLEN-1:0]                         op_a,
  output logic [XLEN-1:0]                         op_b,
  output logic [XLEN-1:0]                         op_imm,
  output logic [3:0]                              alu_op,
  output logic [rv32i_types::PHYS_REG_IDX:0]      pd_o,
  output logic [rv32i_types::ARCH_REG_IDX:0]      rd_o,
  output logic [$clog2(rv32i_types::NUM_ROB_ENTRIES)-1:0] rob_o,
  output logic                                    dest_we_o,
  output logic                                  rob_src_we,
  output logic [$clog2(NUM_ROB_ENTRIES)-1:0] rob_src_idx,
  output logic [31:0]                 rob_src_rs1_val,
  output logic [31:0]                 rob_src_rs2_val,

  input logic [2:0] sub_op_i, //from dispatch
  output logic [2:0] sub_op_o, //to the FU

  input  logic flush,
  input  logic [31:0] pc_i,
  input  logic [6:0]  opcode_i,
  input  logic [2:0]  funct3_i,
  
  output logic [31:0] pc_o,
  output logic [6:0]  opcode_o,
  output logic [2:0]  funct3_o
);

  // State
  row_t rows_q [ENTRIES];
  row_t rows_d [ENTRIES];
  logic [15:0] age_ctr_q, age_ctr_d;
  wire issue_fire;
  logic has_older_busy;
  logic s1_fwd_hit, s2_fwd_hit;
  row_t issue_row;

  // Vacancy and ready bitmaps
  logic [ENTRIES-1:0] vacant_bm;
  logic [ENTRIES-1:0] ready_bm;

  // Selected indices
  integer unsigned enq_idx;
  integer unsigned iss_idx_c;
  logic        has_issue;

  // --------- Combinational next-state and selects ----------
  always_comb begin
    rows_d    = rows_q;
    age_ctr_d = age_ctr_q;

    // Vacancy and ready maps (guard busy with case equality)
    for (integer i = 0; i < ENTRIES; i++) begin
      vacant_bm[i] = (rows_q[i].busy == 1'b0);
      ready_bm[i]  = (rows_q[i].busy == 1'b1) &&
                     rows_q[i].rs1_rdy && rows_q[i].rs2_rdy;
    end

    // enq_ready and enq_idx (lowest index vacant)
    enq_ready = |vacant_bm;
    enq_idx   = 0;
    if (enq_ready) begin
      for (integer unsigned i = 0; i < ENTRIES; i++) if (vacant_bm[i]) begin enq_idx = i; break; end
    end

    // Wakeup via CDB (only touch rows_d)
    if (cdb_valid) begin
      for (integer i = 0; i < ENTRIES; i++) if (rows_q[i].busy == 1'b1) begin
        if (!rows_q[i].rs1_rdy && rows_q[i].ps1 == cdb_pid) rows_d[i].rs1_rdy = 1'b1;
        if (!rows_q[i].rs2_rdy && rows_q[i].ps2 == cdb_pid) rows_d[i].rs2_rdy = 1'b1;
      end
    end

    // Enqueue
    if (enq_valid && enq_ready) begin
      rows_d[enq_idx]        = '0;
      rows_d[enq_idx].busy    = 1'b1;
      rows_d[enq_idx].ps1     = ps1_i;
      rows_d[enq_idx].ps2     = ps2_i;
      rows_d[enq_idx].rs1_rdy = rs1_ready_i || (cdb_valid && (ps1_i == cdb_pid));
      rows_d[enq_idx].rs2_rdy = rs2_ready_i || (cdb_valid && (ps2_i == cdb_pid));
      rows_d[enq_idx].imm     = imm_i;
      rows_d[enq_idx].aop     = alu_op_i;
      rows_d[enq_idx].pd      = pd_i;
      rows_d[enq_idx].rd      = rd_i;
      rows_d[enq_idx].rob     = rob_i;
      rows_d[enq_idx].dest_we = dest_we_i;
      rows_d[enq_idx].age     = age_ctr_q;
      rows_d[enq_idx].sub_op  = sub_op_i; //from dispatch
      rows_d[enq_idx].pc      = pc_i;
      rows_d[enq_idx].opcode  = opcode_i;
      rows_d[enq_idx].funct3  = funct3_i;
      age_ctr_d               = age_ctr_q + 16'd1;

    end

    // Free the issued row
    if (issue_valid && issue_ready) begin
      rows_d[iss_idx_c] = '0;
    end
  end

  // Oldest-ready pick with valid flag + best-age
  function automatic void pick_ready_oldest(
    input  row_t arr [ENTRIES],
    output integer unsigned idx,
    output logic        found
  );
    logic [15:0] best_age;
    found    = 1'b0;
    idx      = '0;
    best_age = 16'hFFFF;
    for (integer unsigned i = 0; i < ENTRIES; i++) begin
      if ((arr[i].busy == 1'b1) && arr[i].rs1_rdy && arr[i].rs2_rdy) begin
        if (!found || (arr[i].age < best_age)) begin
          found    = 1'b1;
          idx      = i;
          best_age = arr[i].age;
        end
      end
    end
  endfunction

  always_comb begin
    pick_ready_oldest(rows_q, iss_idx_c, has_issue);
  end

  always_comb begin
    issue_row = rows_q[iss_idx_c];
  end

  always_comb begin
    has_older_busy = 1'b0;
    if (FORCE_IN_ORDER && has_issue) begin
      for (integer unsigned i = 0; i < ENTRIES; i++) begin
        if ((rows_q[i].busy == 1'b1) &&
            (rows_q[i].age < issue_row.age) &&
            !(i == iss_idx_c)) begin
          has_older_busy = 1'b1;
        end
      end
    end
  end

  assign issue_valid = has_issue && (!FORCE_IN_ORDER || !has_older_busy);

  // Drive PRF/FU outputs from selected entry, or zeros
  // assign prf_rs1_pid = has_issue ? rows_q[iss_idx_c].ps1 : '0;
  // assign prf_rs2_pid = has_issue ? rows_q[iss_idx_c].ps2 : '0;
  assign prf_rs1_pid = issue_row.ps1;
  assign prf_rs2_pid = issue_row.ps2;
  assign s1_fwd_hit = cdb_valid && has_issue && (rows_q[iss_idx_c].ps1 == cdb_pid);
  assign s2_fwd_hit = cdb_valid && has_issue && (rows_q[iss_idx_c].ps2 == cdb_pid);

  assign op_a = s1_fwd_hit ? cdb_value : prf_rs1_rdata;
  assign op_b = s2_fwd_hit ? cdb_value : prf_rs2_rdata;
  // assign op_imm      = has_issue ? rows_q[iss_idx_c].imm : '0;
  // assign alu_op      = has_issue ? rows_q[iss_idx_c].aop : '0;
  // assign pd_o        = has_issue ? rows_q[iss_idx_c].pd  : '0;
  // assign rd_o        = has_issue ? rows_q[iss_idx_c].rd  : '0;
  // assign rob_o       = has_issue ? rows_q[iss_idx_c].rob : '0;
  // assign dest_we_o   = has_issue ? rows_q[iss_idx_c].dest_we : 1'b0;
  // assign sub_op_o    = has_issue ? rows_q[iss_idx_c].sub_op : '0;

  assign op_imm    = issue_row.imm;
  assign alu_op    = issue_row.aop;
  assign pd_o      = issue_row.pd;
  assign rd_o      = issue_row.rd;
  assign rob_o     = issue_row.rob;
  assign dest_we_o = issue_valid && issue_row.dest_we;
  assign sub_op_o  = issue_row.sub_op;

  assign issue_fire = issue_valid && issue_ready;

  assign rob_src_we       = issue_fire;
  assign rob_src_idx      = has_issue ? rows_q[iss_idx_c].rob : '0;
  // assign rob_src_rs1_val = op_a;
  // assign rob_src_rs2_val = op_b;
  assign rob_src_rs1_val = issue_fire ? op_a : 32'b0;
  assign rob_src_rs2_val = issue_fire ? op_b : 32'b0;
  // assign pc_o     = has_issue ? rows_q[iss_idx_c].pc : '0;
  // assign opcode_o = has_issue ? rows_q[iss_idx_c].opcode : '0;
  // assign funct3_o = has_issue ? rows_q[iss_idx_c].funct3 : '0;
  assign pc_o     = issue_row.pc;
  assign opcode_o = issue_row.opcode;
  assign funct3_o = issue_row.funct3;
  // --------- Sequential state ---------
  always_ff @(posedge clk) begin
    if (rst || flush) begin
      for (integer i = 0; i < ENTRIES; i++) rows_q[i] <= '0;
      age_ctr_q <= '0;
    end else begin
      rows_q    <= rows_d;
      age_ctr_q <= age_ctr_d;
    end
  end

endmodule
