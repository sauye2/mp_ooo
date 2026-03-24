module lsu 
import rv32i_types::*;
#(
  parameter XLEN = 32
)(
  input  logic clk,
  input  logic rst,
  
  input  logic        req_valid,
  output logic        req_ready,
  input  logic [XLEN-1:0] base_addr,            // rs1 value
  input  logic [XLEN-1:0] offset,              // immediate  
  input  logic [XLEN-1:0] store_data,          // rs2 value for stores
  input  logic [2:0] funct3,
  input  logic is_store,                       // high:store, low:load
  input  logic [ARCH_REG_IDX:0] rd_arch,
  input  logic [PHYS_REG_IDX:0] pd_phys,
  input  logic [$clog2(NUM_ROB_ENTRIES)-1:0] rob_idx,
  input  logic        dest_we,
  
  output logic [31:0] dcache_addr,
  output logic [3:0]  dcache_rmask,
  output logic [3:0]  dcache_wmask,
  output logic [31:0] dcache_wdata,
  input  logic [31:0] dcache_rdata,
  input  logic        dcache_resp,
  
  output logic        resp_valid,
  input  logic        resp_ready,
  output logic [XLEN-1:0] resp_value,
  output logic [ARCH_REG_IDX:0] resp_rd,
  output logic [PHYS_REG_IDX:0] resp_pd,
  output logic [$clog2(NUM_ROB_ENTRIES)-1:0] resp_rob_idx,
  output logic        resp_dest_we
);

  typedef enum logic [1:0] {IDLE, WAIT_CACHE, SEND_RESP} state_t;
  
  state_t state_q, state_d;
  
  logic [31:0] addr_q, addr_d;
  logic [2:0]  funct3_q, funct3_d;
  logic        is_store_q, is_store_d;
  logic [ARCH_REG_IDX:0] rd_q, rd_d;
  logic [PHYS_REG_IDX:0] pd_q, pd_d;
  logic [$clog2(NUM_ROB_ENTRIES)-1:0] rob_q, rob_d;
  logic        dest_we_q, dest_we_d;
  logic [31:0] store_data_q, store_data_d;
  logic [31:0] load_data_q, load_data_d;
  logic        resp_valid_q, resp_valid_d;
  wire [31:0] eff_addr = base_addr + offset;
  logic [3:0]  rmask, wmask;
  logic [31:0] aligned_wdata;
  logic [31:0] final_load_value;
  
  always_comb begin
    rmask = 4'b0000;
    wmask = 4'b0000;
    aligned_wdata = '0;
    
    if (!is_store_q) begin
      unique case (funct3_q)
        3'b000, 3'b100: begin          // lb, lbu
          rmask = 4'b0001 << addr_q[1:0];
        end
        3'b001, 3'b101: begin          // lh, lhu
          rmask = (addr_q[1]) ? 4'b1100 : 4'b0011;
        end
        3'b010: begin                  // lw
          rmask = 4'b1111;
        end
        default: rmask = 4'b0000;
      endcase
    end else begin
      unique case (funct3_q)
        3'b000: begin                  // sb
          wmask = 4'b0001 << addr_q[1:0];
          unique case (addr_q[1:0])
            2'b00: aligned_wdata = {24'b0, store_data_q[7:0]};
            2'b01: aligned_wdata = {16'b0, store_data_q[7:0], 8'b0};
            2'b10: aligned_wdata = {8'b0, store_data_q[7:0], 16'b0};
            2'b11: aligned_wdata = {store_data_q[7:0], 24'b0};
          endcase
        end
        3'b001: begin                  // sh
          wmask = (addr_q[1]) ? 4'b1100 : 4'b0011;
          aligned_wdata = addr_q[1] ? {store_data_q[15:0], 16'b0} : {16'b0, store_data_q[15:0]};
        end
        3'b010: begin                  // sw
          wmask = 4'b1111;
          aligned_wdata = store_data_q;
        end
        default: begin
          wmask = 4'b0000;
          aligned_wdata = '0;
        end
      endcase
    end
  end
  
  always_comb begin
    final_load_value = '0;
    unique case (funct3_q)
      3'b000: begin             // lb - sign extend
        case (addr_q[1:0])
          2'b00: final_load_value = {{24{load_data_q[7]}}, load_data_q[7:0]};
          2'b01: final_load_value = {{24{load_data_q[15]}}, load_data_q[15:8]};
          2'b10: final_load_value = {{24{load_data_q[23]}}, load_data_q[23:16]};
          2'b11: final_load_value = {{24{load_data_q[31]}}, load_data_q[31:24]};
        endcase
      end
      3'b100: begin              // lbu - zero extend
        case (addr_q[1:0])
          2'b00: final_load_value = {24'b0, load_data_q[7:0]};
          2'b01: final_load_value = {24'b0, load_data_q[15:8]};
          2'b10: final_load_value = {24'b0, load_data_q[23:16]};
          2'b11: final_load_value = {24'b0, load_data_q[31:24]};
        endcase
      end
      3'b001: begin             // lh- sign extend
        if (addr_q[1])
          final_load_value = {{16{load_data_q[31]}}, load_data_q[31:16]};
        else
          final_load_value = {{16{load_data_q[15]}}, load_data_q[15:0]};
      end
      3'b101: begin             // lhu - zero extend
        if (addr_q[1])
          final_load_value = {16'b0, load_data_q[31:16]};
        else
          final_load_value = {16'b0, load_data_q[15:0]};
      end
      3'b010: begin             // lw - no extend
        final_load_value = load_data_q;
      end
      default: final_load_value = '0;
    endcase
  end
  
  always_comb begin
    state_d = state_q;
    addr_d = addr_q;
    funct3_d = funct3_q;
    is_store_d = is_store_q;
    rd_d = rd_q;
    pd_d = pd_q;
    rob_d = rob_q;
    dest_we_d = dest_we_q;
    store_data_d = store_data_q;
    load_data_d = load_data_q;
    resp_valid_d = resp_valid_q;
    req_ready = (state_q == IDLE);
    if (rst) req_ready = 1'b0;
    dcache_addr = '0;
    dcache_rmask = '0;
    dcache_wmask = '0;
    dcache_wdata = '0;
    
    unique case (state_q)
      IDLE: begin
        req_ready = 1'b1;
        if (req_valid) begin
          addr_d = eff_addr;
          funct3_d = funct3;
          is_store_d = is_store;
          rd_d = rd_arch;
          pd_d = pd_phys;
          rob_d = rob_idx;
          dest_we_d = dest_we;
          store_data_d = store_data;
          state_d = WAIT_CACHE;
        end
      end
      
      WAIT_CACHE: begin
        dcache_addr = {addr_q[31:2], 2'b00};
        dcache_rmask = rmask;
        dcache_wmask = wmask;
        dcache_wdata = aligned_wdata;
        
        if (dcache_resp) begin
          if (!is_store_q) begin
            load_data_d = dcache_rdata;
            resp_valid_d = 1'b1;
            state_d = SEND_RESP;
          end else begin
            resp_valid_d = 1'b1;
            state_d = SEND_RESP;
          end
        end else begin
          state_d = WAIT_CACHE;
        end
      end
      
      SEND_RESP: begin
        if (resp_ready || !resp_valid_q) begin
          resp_valid_d = 1'b0;
          state_d = IDLE;
        end
      end
      
      default: state_d = IDLE;
    endcase
  end
  
  always_ff @(posedge clk) begin
    if (rst) begin
      state_q <= IDLE;
      addr_q <= '0;
      funct3_q <= '0;
      is_store_q <= 1'b0;
      rd_q <= '0;
      pd_q <= '0;
      rob_q <= '0;
      dest_we_q <= 1'b0;
      store_data_q <= '0;
      load_data_q <= '0;
      resp_valid_q <= 1'b0;
    end else begin
      state_q <= state_d;
      addr_q <= addr_d;
      funct3_q <= funct3_d;
      is_store_q <= is_store_d;
      rd_q <= rd_d;
      pd_q <= pd_d;
      rob_q <= rob_d;
      dest_we_q <= dest_we_d;
      store_data_q <= store_data_d;
      load_data_q <= load_data_d;
      resp_valid_q <= resp_valid_d;
    end
  end
  
  assign resp_valid = resp_valid_q;
  assign resp_value = is_store_q ? '0 : final_load_value;  // stores dont produce a value
  assign resp_rd = rd_q;
  assign resp_pd = pd_q;
  assign resp_rob_idx = rob_q;
  assign resp_dest_we = dest_we_q && !is_store_q;  // only loads write

endmodule : lsu
