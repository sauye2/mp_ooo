// OpenRAM SRAM model
// Words: 16
// Word size: 256
// Write size: 8

module sram(
`ifdef USE_POWER_PINS
    vdd,
    gnd,
`endif
// Port 0: RW
    clk0,csb0,web0,wmask0,addr0,din0,dout0,
// Port 1: RW
    clk1,csb1,web1,wmask1,addr1,din1,dout1
  );

  parameter NUM_WMASKS = 32 ;
  parameter DATA_WIDTH = 256 ;
  parameter ADDR_WIDTH = 4 ;
  parameter RAM_DEPTH = 1 << ADDR_WIDTH;

`ifdef USE_POWER_PINS
    inout vdd;
    inout gnd;
`endif
  input  clk0; // clock
  input   csb0; // active low chip select
  input  web0; // active low write control
  input [ADDR_WIDTH-1:0]  addr0;
  input [NUM_WMASKS-1:0]   wmask0; // write mask
  input [DATA_WIDTH-1:0]  din0;
  output [DATA_WIDTH-1:0] dout0;
  input  clk1; // clock
  input   csb1; // active low chip select
  input  web1; // active low write control
  input [ADDR_WIDTH-1:0]  addr1;
  input [NUM_WMASKS-1:0]   wmask1; // write mask
  input [DATA_WIDTH-1:0]  din1;
  output [DATA_WIDTH-1:0] dout1;

  reg [DATA_WIDTH-1:0]    mem [0:RAM_DEPTH-1];

  reg  web0_reg;
  initial web0_reg = 1'b1;
  reg [NUM_WMASKS-1:0]   wmask0_reg;
  reg [ADDR_WIDTH-1:0]  addr0_reg;
  reg [DATA_WIDTH-1:0]  din0_reg;
  reg [DATA_WIDTH-1:0]  dout0;

  always @(posedge clk0)
  begin
    if( !csb0 ) begin
      web0_reg <= web0;
      wmask0_reg <= wmask0;
      addr0_reg <= addr0;
      din0_reg <= din0;
    end
  end

  reg  web1_reg;
  initial web1_reg = 1'b1;
  reg [NUM_WMASKS-1:0]   wmask1_reg;
  reg [ADDR_WIDTH-1:0]  addr1_reg;
  reg [DATA_WIDTH-1:0]  din1_reg;
  reg [DATA_WIDTH-1:0]  dout1;

  always @(posedge clk1)
  begin
    if( !csb1 ) begin
      web1_reg <= web1;
      wmask1_reg <= wmask1;
      addr1_reg <= addr1;
      din1_reg <= din1;
    end
  end


  always @ (posedge clk0)
  begin : MEM_WRITE0
    if ( !web0_reg ) begin
        if (wmask0_reg[0])
                mem[addr0_reg][7:0] <= din0_reg[7:0];
        if (wmask0_reg[1])
                mem[addr0_reg][15:8] <= din0_reg[15:8];
        if (wmask0_reg[2])
                mem[addr0_reg][23:16] <= din0_reg[23:16];
        if (wmask0_reg[3])
                mem[addr0_reg][31:24] <= din0_reg[31:24];
        if (wmask0_reg[4])
                mem[addr0_reg][39:32] <= din0_reg[39:32];
        if (wmask0_reg[5])
                mem[addr0_reg][47:40] <= din0_reg[47:40];
        if (wmask0_reg[6])
                mem[addr0_reg][55:48] <= din0_reg[55:48];
        if (wmask0_reg[7])
                mem[addr0_reg][63:56] <= din0_reg[63:56];
        if (wmask0_reg[8])
                mem[addr0_reg][71:64] <= din0_reg[71:64];
        if (wmask0_reg[9])
                mem[addr0_reg][79:72] <= din0_reg[79:72];
        if (wmask0_reg[10])
                mem[addr0_reg][87:80] <= din0_reg[87:80];
        if (wmask0_reg[11])
                mem[addr0_reg][95:88] <= din0_reg[95:88];
        if (wmask0_reg[12])
                mem[addr0_reg][103:96] <= din0_reg[103:96];
        if (wmask0_reg[13])
                mem[addr0_reg][111:104] <= din0_reg[111:104];
        if (wmask0_reg[14])
                mem[addr0_reg][119:112] <= din0_reg[119:112];
        if (wmask0_reg[15])
                mem[addr0_reg][127:120] <= din0_reg[127:120];
        if (wmask0_reg[16])
                mem[addr0_reg][135:128] <= din0_reg[135:128];
        if (wmask0_reg[17])
                mem[addr0_reg][143:136] <= din0_reg[143:136];
        if (wmask0_reg[18])
                mem[addr0_reg][151:144] <= din0_reg[151:144];
        if (wmask0_reg[19])
                mem[addr0_reg][159:152] <= din0_reg[159:152];
        if (wmask0_reg[20])
                mem[addr0_reg][167:160] <= din0_reg[167:160];
        if (wmask0_reg[21])
                mem[addr0_reg][175:168] <= din0_reg[175:168];
        if (wmask0_reg[22])
                mem[addr0_reg][183:176] <= din0_reg[183:176];
        if (wmask0_reg[23])
                mem[addr0_reg][191:184] <= din0_reg[191:184];
        if (wmask0_reg[24])
                mem[addr0_reg][199:192] <= din0_reg[199:192];
        if (wmask0_reg[25])
                mem[addr0_reg][207:200] <= din0_reg[207:200];
        if (wmask0_reg[26])
                mem[addr0_reg][215:208] <= din0_reg[215:208];
        if (wmask0_reg[27])
                mem[addr0_reg][223:216] <= din0_reg[223:216];
        if (wmask0_reg[28])
                mem[addr0_reg][231:224] <= din0_reg[231:224];
        if (wmask0_reg[29])
                mem[addr0_reg][239:232] <= din0_reg[239:232];
        if (wmask0_reg[30])
                mem[addr0_reg][247:240] <= din0_reg[247:240];
        if (wmask0_reg[31])
                mem[addr0_reg][255:248] <= din0_reg[255:248];
    end
  end

  always @ (*)
  begin : MEM_READ0
    dout0 = mem[addr0_reg];
  end

  always @ (posedge clk1)
  begin : MEM_WRITE1
    if ( !web1_reg ) begin
        if (wmask1_reg[0])
                mem[addr1_reg][7:0] <= din1_reg[7:0];
        if (wmask1_reg[1])
                mem[addr1_reg][15:8] <= din1_reg[15:8];
        if (wmask1_reg[2])
                mem[addr1_reg][23:16] <= din1_reg[23:16];
        if (wmask1_reg[3])
                mem[addr1_reg][31:24] <= din1_reg[31:24];
        if (wmask1_reg[4])
                mem[addr1_reg][39:32] <= din1_reg[39:32];
        if (wmask1_reg[5])
                mem[addr1_reg][47:40] <= din1_reg[47:40];
        if (wmask1_reg[6])
                mem[addr1_reg][55:48] <= din1_reg[55:48];
        if (wmask1_reg[7])
                mem[addr1_reg][63:56] <= din1_reg[63:56];
        if (wmask1_reg[8])
                mem[addr1_reg][71:64] <= din1_reg[71:64];
        if (wmask1_reg[9])
                mem[addr1_reg][79:72] <= din1_reg[79:72];
        if (wmask1_reg[10])
                mem[addr1_reg][87:80] <= din1_reg[87:80];
        if (wmask1_reg[11])
                mem[addr1_reg][95:88] <= din1_reg[95:88];
        if (wmask1_reg[12])
                mem[addr1_reg][103:96] <= din1_reg[103:96];
        if (wmask1_reg[13])
                mem[addr1_reg][111:104] <= din1_reg[111:104];
        if (wmask1_reg[14])
                mem[addr1_reg][119:112] <= din1_reg[119:112];
        if (wmask1_reg[15])
                mem[addr1_reg][127:120] <= din1_reg[127:120];
        if (wmask1_reg[16])
                mem[addr1_reg][135:128] <= din1_reg[135:128];
        if (wmask1_reg[17])
                mem[addr1_reg][143:136] <= din1_reg[143:136];
        if (wmask1_reg[18])
                mem[addr1_reg][151:144] <= din1_reg[151:144];
        if (wmask1_reg[19])
                mem[addr1_reg][159:152] <= din1_reg[159:152];
        if (wmask1_reg[20])
                mem[addr1_reg][167:160] <= din1_reg[167:160];
        if (wmask1_reg[21])
                mem[addr1_reg][175:168] <= din1_reg[175:168];
        if (wmask1_reg[22])
                mem[addr1_reg][183:176] <= din1_reg[183:176];
        if (wmask1_reg[23])
                mem[addr1_reg][191:184] <= din1_reg[191:184];
        if (wmask1_reg[24])
                mem[addr1_reg][199:192] <= din1_reg[199:192];
        if (wmask1_reg[25])
                mem[addr1_reg][207:200] <= din1_reg[207:200];
        if (wmask1_reg[26])
                mem[addr1_reg][215:208] <= din1_reg[215:208];
        if (wmask1_reg[27])
                mem[addr1_reg][223:216] <= din1_reg[223:216];
        if (wmask1_reg[28])
                mem[addr1_reg][231:224] <= din1_reg[231:224];
        if (wmask1_reg[29])
                mem[addr1_reg][239:232] <= din1_reg[239:232];
        if (wmask1_reg[30])
                mem[addr1_reg][247:240] <= din1_reg[247:240];
        if (wmask1_reg[31])
                mem[addr1_reg][255:248] <= din1_reg[255:248];
    end
  end

  always @ (*)
  begin : MEM_READ1
    dout1 = mem[addr1_reg];
  end

endmodule
