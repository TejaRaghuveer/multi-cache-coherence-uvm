//------------------------------------------------------------------------------
// cache_state_pkg.sv
//------------------------------------------------------------------------------
package cache_state_pkg;
  typedef enum logic [2:0] {
    MESI_I = 3'b000,
    MESI_S = 3'b001,
    MESI_E = 3'b010,
    MESI_M = 3'b011,
    MESI_O = 3'b100
  } mesi_state_e;

  typedef enum logic [2:0] {
    TX_NOP,
    TX_PR_RD,
    TX_PR_WR,
    TX_BUS_RD,
    TX_BUS_RDX,
    TX_BUS_UPGR,
    TX_BUS_INV,
    TX_WB
  } coh_txn_e;

  typedef struct packed {
    logic [31:0] addr;
    logic [63:0] data;
    coh_txn_e    txn;
    mesi_state_e state_before;
    mesi_state_e state_after;
    string       src;
    int unsigned core_id;
    int unsigned sharer_count;
  } coh_event_s;
endpackage
