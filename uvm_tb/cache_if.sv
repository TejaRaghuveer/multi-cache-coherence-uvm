//------------------------------------------------------------------------------
// cache_if.sv
//------------------------------------------------------------------------------
interface cache_if #(parameter ADDR_WIDTH = 32, DATA_WIDTH = 64) (input logic clk, rst_n);
  // Request channel
  logic                  req;
  logic                  gnt;
  logic [ADDR_WIDTH-1:0] addr;
  logic [DATA_WIDTH-1:0] wdata;
  logic                  we;

  // Read return channel
  logic                  valid;
  logic [DATA_WIDTH-1:0] rdata;
  logic                  ready;

  // Coherence sideband
  logic [2:0]            snoop_cmd;
  logic [1:0]            snoop_resp;
  logic [15:0]           sharer_vec;
  logic                  victim_evict;
endinterface
