// test new test
package rv32i_types;

  // --------- core widths (minimal set needed by the structs) ---------
  localparam integer NUM_ARCH_REG    = 32;                         // x0..x31
  localparam integer NUM_ROB_ENTRIES = 32;                          // tweak as needed
  localparam integer NUM_PHYS_REG    = NUM_ARCH_REG + NUM_ROB_ENTRIES; // simple baseline
  localparam integer ARCH_REG_IDX    = $clog2(NUM_ARCH_REG) - 1;   // bits-1 for arch reg index
  localparam integer PHYS_REG_IDX    = $clog2(NUM_PHYS_REG) - 1;   // bits-1 for physical reg index
  typedef logic [PHYS_REG_IDX:0] pd_t;

  // ---------- CDB (no branch fields, no pc_next_calc) ----------
  typedef struct packed {
      logic [ARCH_REG_IDX:0]  rd;
      logic [PHYS_REG_IDX:0]  pd;
      logic                   valid;
      logic [$clog2(NUM_ROB_ENTRIES)-1:0] rob_entry_idx;

      logic [31:0] rs1_value, rs2_value, value;
      logic [6:0]  opcode;
      logic [31:0] pc;
      logic exc;

      logic is_ctrl;
      logic br_taken;
      logic [31:0] br_target;

    //   logic [31:0] mem_addr;
    //   logic [3:0]  mem_rmask;
    //   logic [3:0]  mem_wmask;
    //   logic [31:0] mem_rdata;
    //   logic [31:0] mem_wdata;
  } cdb_entry_t;

  // ---------- Rename <-> RAT ----------
  typedef struct packed {
      logic [ARCH_REG_IDX:0] rs1, rs2, rd;
      logic                  rd_alloc;   // allocate a new physical for rd in this uop
      // Rename/freelist chooses the physical; RAT just applies it
      logic [PHYS_REG_IDX:0] pd_new;     // physical chosen by rename/freelist
      logic alloc_ok; //has the freelist freed a physical reg to rename stage
      logic commit;  // 1 iff DISPATCH FIRES THIS CYCLE for a writer
  } ren_to_rat_req_t;


  typedef struct packed {
      logic [PHYS_REG_IDX:0] ps1, ps2, pd_new;
      logic                  ps1_valid, ps2_valid;
      logic                  pd_valid;   // allocation succeeded
      logic [PHYS_REG_IDX:0] rd_old_pd;    // previous physical mapped to rd
  } rat_to_ren_rsp_t;

  // ---------- Dispatch -> ROB (data for new ROB row) ----------
  typedef struct packed {
      logic [ARCH_REG_IDX:0] rd;
      logic [PHYS_REG_IDX:0] pd;
      logic [PHYS_REG_IDX:0] pd_old;
      logic                  dest_we;

      logic [31:0] pc;
      logic [63:0] order;

      logic [6:0]  opcode;
      logic        enqueue_rob;
      logic is_rob_full;
      logic [4:0] rob_entry_idx;
      logic [31:0] inst;
      logic [4:0]            rs1, rs2;
      logic                  uses_rs1, uses_rs2;
      logic br_taken;
      logic [31:0] br_target;
      logic        is_branch;
      logic [7:0]  bht_idx;
      logic        pred_taken;
      logic [31:0]  pred_target;
  } dispatch_to_ROB_t;

//   typedef struct packed {
//       dispatch_to_ROB_only_data_t dispatch_to_ROB_only_data;
//       logic                       enqueue_rob;
//   } dispatch_to_ROB_t;

  // ---------- ROB entry (stored per row; no branch/rvfi fields) ----------
  typedef struct packed {
      // static at allocate
      logic [ARCH_REG_IDX:0] rd;
      logic [PHYS_REG_IDX:0] pd;
      logic [PHYS_REG_IDX:0] pd_old;
      logic                  dest_we;
      logic [6:0]            opcode;
      logic [31:0]           pc;
      logic [63:0]           order;
      logic [31:0]           inst;

      // dynamic as it executes
      logic                  ready;              // result is ready to commit
      logic [31:0]           value;              // commit value (or store data)
      logic                  exc;                // exception flag
      logic [3:0]            exc_cause;          // optional cause
      logic [4:0]            rs1, rs2;    
      logic [31:0]           rs1_value, rs2_value; 
      logic uses_rs1, uses_rs2;    

      // memory bookkeeping for stores (commit tme)
      logic [31:0]           mem_addr;
      logic [3:0]            mem_wmask;
      logic [31:0]           mem_wdata;

      // optional: latch whether this row is marked to commit this cycle
      logic                  commit;

      logic                  br_taken;
      logic [31:0]           br_target;
      logic         is_branch;          // marks this entry as a control-flow branch
      logic [7:0]   bht_idx;           
      logic         pred_taken; 
      logic [31:0]  pred_target;    
  } ROB_entry_t;

    typedef struct packed {
    logic valid;
    logic is_store;
    logic done;
    logic [31:0] ea;
    logic [31:0] word_addr;
    logic [1:0] a10;
    logic [2:0] f3;
    logic [$clog2(NUM_ROB_ENTRIES)-1:0] rob;
    logic [PHYS_REG_IDX:0] pd_s;
    logic [ARCH_REG_IDX:0] rd_s;
    logic [31:0] value;
    logic [31:0] wword;
    logic [3:0] wmask;
  } lsq_entry_t;

  // ---------- ROB <-> Dispatch backpressure ----------
  typedef struct packed {
      logic [$clog2(NUM_ROB_ENTRIES)-1:0] rob_entry_idx; // next free (tail)
      logic                               is_rob_full;
  } ROB_to_dispatch_t;

  // ---------- ROB <-> Commit side (RRAT/RRF) ----------
  typedef struct packed {
      ROB_entry_t                         rob_entry;     // head entry when !empty
      logic                               is_rob_empty;
  } ROB_to_RRF_t;

  typedef struct packed {
      logic dequeue;                                     // advance head
  } RRF_to_ROB_t;

  // ---------- RRAT checkpoint (for precise recovery) ----------
  typedef struct packed {
      logic [ARCH_REG_IDX:0] rd;
      logic [PHYS_REG_IDX:0] old_pd;    // previously mapped phys reg for rd
      logic [PHYS_REG_IDX:0] new_pd;    // newly allocated phys reg for rd
      logic                  dest_we;   // meaningful when uop writes a dest
  } rrat_checkpoint_t;

  typedef struct packed {
    logic busy;
    logic [rv32i_types::PHYS_REG_IDX:0] ps1, ps2;
    logic rs1_rdy, rs2_rdy;     // tracked via CDB
    logic [32-1:0]            imm;
    logic [3:0]                 aop;
    logic [rv32i_types::PHYS_REG_IDX:0] pd;
    logic [rv32i_types::ARCH_REG_IDX:0] rd;
    logic [$clog2(rv32i_types::NUM_ROB_ENTRIES)-1:0] rob;
    logic dest_we;
    logic [15:0] age;
    logic [2:0] sub_op;
    logic [31:0] pc;
    logic [6:0]  opcode;
    logic [2:0]  funct3;
  } row_t;

  typedef struct packed {
      logic valid;
      logic done;
      logic [31:0] ea;
      logic [31:0] word_addr;
      logic [1:0] a10;
      logic [2:0] f3;
      logic [$clog2(NUM_ROB_ENTRIES)-1:0] rob;
      logic [PHYS_REG_IDX:0] pd_s;
      logic [ARCH_REG_IDX:0] rd_s;
      logic [31:0] value;
    } lq_t;

  typedef struct packed {
    logic valid;
    logic committed;
    logic [31:0] ea;
    logic [31:0] word_addr;
    logic [1:0] a10;
    logic [2:0] f3;
    logic [$clog2(NUM_ROB_ENTRIES)-1:0] rob;
    logic [31:0] wword;
    logic [3:0] wmask;
    logic [PHYS_REG_IDX:0] ps2;
  } sq_t;

  typedef struct packed {
    logic        valid;
    logic [31:0] addr;
    logic [3:0]  wmask;
    logic [31:0] wdata;
  } pcsb_entry_t;

typedef enum logic [6:0] {
    op_b_lui       = 7'b0110111, // load upper immediate (U type)
    op_b_auipc     = 7'b0010111, // add upper immediate PC (U type)
    op_b_jal       = 7'b1101111, // jump and link (J type)
    op_b_jalr      = 7'b1100111, // jump and link register (I type)
    op_b_br        = 7'b1100011, // branch (B type)
    op_b_load      = 7'b0000011, // load (I type)
    op_b_store     = 7'b0100011, // store (S type)
    op_b_imm       = 7'b0010011, // arith ops with register/immediate operands (I type)
    op_b_reg       = 7'b0110011  // arith ops with register operands (R type)
} rv32i_opcode;

typedef enum logic [2:0] {
    arith_f3_add   = 3'b000, // check logic 30 for sub if op_reg op
    arith_f3_sll   = 3'b001,
    arith_f3_slt   = 3'b010,
    arith_f3_sltu  = 3'b011,
    arith_f3_xor   = 3'b100,
    arith_f3_sr    = 3'b101, // check logic 30 for logical/arithmetic
    arith_f3_or    = 3'b110,
    arith_f3_and   = 3'b111
} arith_f3_t;

typedef enum logic [2:0] { 
    arith_f3_mul    = 3'b000,
    arith_f3_mulh   = 3'b001,
    arith_f3_mulhsu = 3'b010,
    arith_f3_mulhu  = 3'b011,
    arith_f3_div    = 3'b100,
    arith_f3_divu   = 3'b101,
    arith_f3_rem    = 3'b110,
    arith_f3_remu   = 3'b111
} mul_div_rem_f3_t;

typedef enum logic [2:0] {
    load_f3_lb     = 3'b000,
    load_f3_lh     = 3'b001,
    load_f3_lw     = 3'b010,
    load_f3_lbu    = 3'b100,
    load_f3_lhu    = 3'b101
} load_f3_t;

typedef enum logic [2:0] {
    store_f3_sb    = 3'b000,
    store_f3_sh    = 3'b001,
    store_f3_sw    = 3'b010
} store_f3_t;

typedef enum logic [2:0] {
    branch_f3_beq  = 3'b000,
    branch_f3_bne  = 3'b001,
    branch_f3_blt  = 3'b100,
    branch_f3_bge  = 3'b101,
    branch_f3_bltu = 3'b110,
    branch_f3_bgeu = 3'b111
} branch_f3_t;

typedef enum logic [2:0] {
    alu_op_add     = 3'b000,
    alu_op_sll     = 3'b001,
    alu_op_sra     = 3'b010,
    alu_op_sub     = 3'b011,
    alu_op_xor     = 3'b100,
    alu_op_srl     = 3'b101,
    alu_op_or      = 3'b110,
    alu_op_and     = 3'b111
} alu_ops;

typedef union packed {
    logic [31:0] word;

    struct packed {
        logic [11:0] i_imm;
        logic [4:0]  rs1;
        logic [2:0]  funct3;
        logic [4:0]  rd;
        rv32i_opcode opcode;
    } i_type;

    struct packed {
        logic [6:0]  funct7;
        logic [4:0]  rs2;
        logic [4:0]  rs1;
        logic [2:0]  funct3;
        logic [4:0]  rd;
        rv32i_opcode opcode;
    } r_type;

    struct packed {
        logic [11:5] imm_s_top;
        logic [4:0]  rs2;
        logic [4:0]  rs1;
        logic [2:0]  funct3;
        logic [4:0]  imm_s_bot;
        rv32i_opcode opcode;
    } s_type;


    struct packed {
        logic [31:25] imm_b_top;         // top imm is bts 25-31
        logic [4:0]   rs2;
        logic [4:0]   rs1;
        logic [2:0]   funct3;
        logic [11:7]  imm_b_bot;         // bot imm is bts 7-11
        rv32i_opcode  opcode;
    } b_type;

    struct packed {
        logic [31:12] imm;
        logic [4:0]   rd;
        rv32i_opcode  opcode;
    } j_type;

} instr_t;

// add your types in this file if needed.
typedef enum logic [6:0] {
    base           = 7'b0000000,
    variant        = 7'b0100000,
    rv32m_var      = 7'b0000001
} funct7_t;
    
endpackage: rv32i_types