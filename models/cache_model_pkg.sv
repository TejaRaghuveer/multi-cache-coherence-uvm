//------------------------------------------------------------------------------
// cache_model_pkg.sv
//------------------------------------------------------------------------------
package cache_model_pkg;
  typedef enum logic [2:0] { I, S, E, M, O } mesi_e;

  typedef struct packed {
    bit         valid;
    mesi_e      state;
    logic [31:0] tag;
    logic [63:0] data;
    bit         dirty;
  } line_s;

  typedef struct packed {
    mesi_e       new_state;
    logic [63:0] data;
    bit          issue_wb;
    bit          hit;
  } txn_result_s;
endpackage
