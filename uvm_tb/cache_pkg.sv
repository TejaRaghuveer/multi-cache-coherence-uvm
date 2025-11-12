//------------------------------------------------------------------------------
// cache_pkg.sv
//------------------------------------------------------------------------------
package cache_pkg;
  import uvm_pkg::*;
  include "uvm_macros.svh"

  import cache_state_pkg::*;
  import cache_model_pkg::*;

  include "coh_sequences.svh"

  class cache_coh_item extends uvm_sequence_item;
    rand logic [31:0] addr;
    rand logic [63:0] data;
    rand coh_txn_e    txn;
    mesi_state_e      state_before;
    mesi_state_e      state_after;
    string            src;
    int unsigned      core_id;
    int unsigned      sharer_count;

    uvm_object_utils_begin(cache_coh_item)
      uvm_field_int(addr, UVM_ALL_ON)
      uvm_field_int(data, UVM_ALL_ON)
      uvm_field_enum(coh_txn_e, txn, UVM_ALL_ON)
      uvm_field_int(core_id, UVM_ALL_ON)
      uvm_field_int(sharer_count, UVM_ALL_ON)
    uvm_object_utils_end

    function new(string name = "cache_coh_item");
      super.new(name);
    endfunction
  endclass

  class cache_state_model extends uvm_object;
    uvm_object_utils(cache_state_model)

    typedef struct packed {
      mesi_state_e state;
      logic [63:0] data;
    } line_info_s;

    protected line_info_s table[string];

    function new(string name = "cache_state_model");
      super.new(name);
    endfunction

    function mesi_state_e get_state(logic [31:0] addr);
      if (!table.exists(addr)) return MESI_I;
      return table[addr].state;
    endfunction

    function void observe(cache_coh_item tr);
      line_info_s info = table.exists(tr.addr) ? table[tr.addr] : '{MESI_I, '0};
      info.state = tr.state_after;
      if (tr.txn inside {TX_PR_WR, TX_BUS_RDX})
        info.data = tr.data;
      table[tr.addr] = info;
    endfunction

    function void invalidate(logic [31:0] addr);
      table.delete(addr);
    endfunction
  endclass

  class cache_vseqr extends uvm_sequencer #(cache_coh_item);
    uvm_component_utils(cache_vseqr)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction
  endclass

  class l1_driver extends uvm_driver #(cache_coh_item);
    uvm_component_utils(l1_driver)

    virtual cache_if vif;
    cache_state_model state_model;
    int core_id;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual cache_if)::get(this, "", "vif", vif))
        uvm_fatal(get_full_name(), "L1 driver requires virtual interface")
      if (!uvm_config_db#(cache_state_model)::get(this, "", "state_model", state_model))
        state_model = cache_state_model::type_id::create("l1_state_model");
      void'(uvm_config_db#(int)::get(this, "", "core_id", core_id));
    endfunction

    task run_phase(uvm_phase phase);
      forever begin
        cache_coh_item tr;
        seq_item_port.get_next_item(tr);
        tr.state_before = state_model.get_state(tr.addr);
        tr.state_after  = predict_next_state(tr.state_before, tr.txn);
        drive_request(tr);
        state_model.observe(tr);
        seq_item_port.item_done();
      end
    endtask

    task drive_request(cache_coh_item tr);
      @(posedge vif.clk);
      vif.req  <= 1;
      vif.addr <= tr.addr;
      vif.we   <= (tr.txn == TX_PR_WR);
      vif.wdata<= tr.data;
      do @(posedge vif.clk); while (!vif.gnt);
      vif.req <= 0;
      if (!vif.we) begin
        do @(posedge vif.clk); while (!vif.valid);
        tr.data = vif.rdata;
      end
    endtask

    function mesi_state_e predict_next_state(mesi_state_e cur, coh_txn_e txn);
      case (cur)
        MESI_I: begin
          case (txn)
            TX_PR_RD : return MESI_E;
            TX_PR_WR,
            TX_BUS_RDX: return MESI_M;
            TX_BUS_RD : return MESI_S;
            default   : return cur;
          endcase
        end
        MESI_S: begin
          case (txn)
            TX_PR_WR,
            TX_BUS_UPGR: return MESI_M;
            TX_BUS_INV,
            TX_BUS_RDX : return MESI_I;
            default     : return cur;
          endcase
        end
        MESI_E: begin
          case (txn)
            TX_PR_WR : return MESI_M;
            TX_BUS_RD: return MESI_S;
            TX_BUS_INV,
            TX_BUS_RDX: return MESI_I;
            default    : return cur;
          endcase
        end
        MESI_M: begin
          case (txn)
            TX_BUS_RD : return MESI_O;
            TX_BUS_INV,
            TX_BUS_RDX,
            TX_WB     : return MESI_I;
            default    : return MESI_M;
          endcase
        end
        MESI_O: begin
          case (txn)
            TX_PR_WR : return MESI_M;
            TX_BUS_INV,
            TX_BUS_RDX,
            TX_WB     : return MESI_I;
            default    : return MESI_O;
          endcase
        end
        default: return cur;
      endcase
    endfunction
  endclass

  class l1_monitor extends uvm_monitor;
    uvm_component_utils(l1_monitor)

    virtual cache_if vif;
    cache_state_model state_model;
    uvm_analysis_port #(cache_coh_item) ap;
    uvm_analysis_port #(cache_coh_item) trace_ap;
    int core_id;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
      trace_ap = new("trace_ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual cache_if)::get(this, "", "vif", vif))
        uvm_fatal(get_full_name(), "L1 monitor requires virtual interface")
      if (!uvm_config_db#(cache_state_model)::get(this, "", "state_model", state_model))
        state_model = cache_state_model::type_id::create("l1_state_model_mon");
      void'(uvm_config_db#(int)::get(this, "", "core_id", core_id));
    endfunction

    task run_phase(uvm_phase phase);
      forever begin
        @(posedge vif.clk);
        if (vif.req && vif.gnt) begin
          cache_coh_item tr = cache_coh_item::type_id::create("l1_tr");
          tr.addr         = vif.addr;
          tr.txn          = decode_txn();
          tr.data         = vif.we ? vif.wdata : vif.rdata;
          tr.state_before = state_model.get_state(tr.addr);
          tr.state_after  = predict_next_state(tr.state_before, tr.txn);
          tr.src          = "L1";
          tr.core_id      = core_id;
          tr.sharer_count = count_sharers(vif.sharer_vec);
          ap.write(tr);
          trace_ap.write(tr);
        end
      end
    endtask

    function coh_txn_e decode_txn();
      if (vif.victim_evict) return TX_WB;
      if (vif.we) return TX_PR_WR;
      return TX_PR_RD;
    endfunction

    function mesi_state_e predict_next_state(mesi_state_e cur, coh_txn_e txn);
      case (cur)
        MESI_I: begin
          case (txn)
            TX_PR_RD : return MESI_E;
            TX_PR_WR,
            TX_BUS_RDX: return MESI_M;
            TX_BUS_RD : return MESI_S;
            default   : return cur;
          endcase
        end
        MESI_S: begin
          case (txn)
            TX_PR_WR,
            TX_BUS_UPGR: return MESI_M;
            TX_BUS_INV,
            TX_BUS_RDX : return MESI_I;
            default     : return cur;
          endcase
        end
        MESI_E: begin
          case (txn)
            TX_PR_WR : return MESI_M;
            TX_BUS_RD: return MESI_S;
            TX_BUS_INV,
            TX_BUS_RDX: return MESI_I;
            default    : return cur;
          endcase
        end
        MESI_M: begin
          case (txn)
            TX_BUS_RD : return MESI_O;
            TX_BUS_INV,
            TX_BUS_RDX,
            TX_WB     : return MESI_I;
            default    : return MESI_M;
          endcase
        end
        MESI_O: begin
          case (txn)
            TX_PR_WR : return MESI_M;
            TX_BUS_INV,
            TX_BUS_RDX,
            TX_WB     : return MESI_I;
            default    : return MESI_O;
          endcase
        end
        default: return cur;
      endcase
    endfunction

    function mesi_state_e predict_next_state(mesi_state_e cur, coh_txn_e txn);
      case (txn)
        TX_BUS_RD: begin
          if (cur == MESI_M) return MESI_O;
          if (cur == MESI_I) return MESI_S;
          return cur;
        end
        TX_BUS_RDX,
        TX_BUS_INV: return MESI_I;
        TX_PR_WR  : return MESI_M;
        TX_WB     : return MESI_I;
        default   : return cur;
      endcase
    endfunction

    function int count_sharers(logic [15:0] sharer_vec);
      return (sharer_vec);
    endfunction
  endclass

  class l1_agent extends uvm_agent;
    uvm_component_utils(l1_agent)

    cache_vseqr       seqr;
    l1_driver         drv;
    l1_monitor        mon;
    cache_state_model state_model;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      seqr = cache_vseqr::type_id::create("seqr", this);
      drv  = l1_driver  ::type_id::create("drv",  this);
      mon  = l1_monitor ::type_id::create("mon",  this);

      if (!uvm_config_db#(cache_state_model)::get(this, "", "shared_state_model", state_model))
        state_model = cache_state_model::type_id::create("shared_state_model", this);

      uvm_config_db#(cache_state_model)::set(this, "drv", "state_model", state_model);
      uvm_config_db#(cache_state_model)::set(this, "mon", "state_model", state_model);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      drv.seq_item_port.connect(seqr.seq_item_export);
    endfunction
  endclass

  class l2_driver extends uvm_driver #(cache_coh_item);
    uvm_component_utils(l2_driver)

    virtual cache_if vif;
    cache_state_model state_model;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual cache_if)::get(this, "", "vif", vif))
        uvm_fatal(get_full_name(), "L2 driver requires virtual interface")
      if (!uvm_config_db#(cache_state_model)::get(this, "", "state_model", state_model))
        state_model = cache_state_model::type_id::create("l2_state_model");
    endfunction

    task run_phase(uvm_phase phase);
      forever begin
        cache_coh_item tr;
        seq_item_port.get_next_item(tr);
        tr.state_before = state_model.get_state(tr.addr);
        tr.state_after  = predict_next_state(tr.state_before, tr.txn);
        respond(tr);
        state_model.observe(tr);
        seq_item_port.item_done();
      end
    endtask

    task respond(cache_coh_item tr);
      @(posedge vif.clk);
      vif.req   <= 1;
      vif.addr  <= tr.addr;
      vif.we    <= (tr.txn inside {TX_PR_WR, TX_BUS_RDX});
      vif.wdata <= tr.data;
      do @(posedge vif.clk); while (!vif.ready);
      vif.req <= 0;
      if (!vif.we) begin
        vif.valid <= 1;
        @(posedge vif.clk);
        vif.valid <= 0;
      end
    endtask

    function mesi_state_e predict_next_state(mesi_state_e cur, coh_txn_e txn);
      case (txn)
        TX_BUS_RD: begin
          if (cur == MESI_M) return MESI_O;
          if (cur == MESI_I) return MESI_S;
          return cur;
        end
        TX_BUS_RDX,
        TX_BUS_INV: return MESI_I;
        TX_PR_WR  : return MESI_M;
        TX_WB     : return MESI_I;
        default   : return cur;
      endcase
    endfunction
  endclass

  class l2_monitor extends uvm_monitor;
    uvm_component_utils(l2_monitor)

    virtual cache_if vif;
    cache_state_model state_model;
    uvm_analysis_port #(cache_coh_item) ap;
    uvm_analysis_port #(cache_coh_item) trace_ap;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
      trace_ap = new("trace_ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual cache_if)::get(this, "", "vif", vif))
        uvm_fatal(get_full_name(), "L2 monitor requires virtual interface")
      if (!uvm_config_db#(cache_state_model)::get(this, "", "state_model", state_model))
        state_model = cache_state_model::type_id::create("l2_state_model_mon");
    endfunction

    task run_phase(uvm_phase phase);
      forever begin
        @(posedge vif.clk);
        if (vif.req && vif.ready) begin
          cache_coh_item tr = cache_coh_item::type_id::create("l2_tr");
          tr.addr         = vif.addr;
          tr.txn          = decode_txn();
          tr.data         = vif.we ? vif.wdata : vif.rdata;
          tr.state_before = state_model.get_state(tr.addr);
          tr.state_after  = predict_next_state(tr.state_before, tr.txn);
          tr.src          = "L2";
          tr.core_id      = -1;
          tr.sharer_count = count_sharers(vif.sharer_vec);
          ap.write(tr);
          trace_ap.write(tr);
        end
      end
    endtask

    function coh_txn_e decode_txn();
      case (vif.snoop_cmd)
        3'b001: return TX_BUS_RD;
        3'b010: return TX_BUS_RDX;
        3'b011: return TX_BUS_UPGR;
        3'b100: return TX_BUS_INV;
        default: if (vif.victim_evict) return TX_WB;
      endcase
      return vif.we ? TX_PR_WR : TX_PR_RD;
    endfunction

    function mesi_state_e predict_next_state(mesi_state_e cur, coh_txn_e txn);
      case (txn)
        TX_BUS_RD: begin
          if (cur == MESI_M) return MESI_O;
          if (cur == MESI_I) return MESI_S;
          return cur;
        end
        TX_BUS_RDX,
        TX_BUS_INV: return MESI_I;
        TX_PR_WR  : return MESI_M;
        TX_WB     : return MESI_I;
        default   : return cur;
      endcase
    endfunction

    function int count_sharers(logic [15:0] sharer_vec);
      return (sharer_vec);
    endfunction
  endclass

  class l2_agent extends uvm_agent;
    uvm_component_utils(l2_agent)

    cache_vseqr       seqr;
    l2_driver         drv;
    l2_monitor        mon;
    cache_state_model state_model;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      seqr = cache_vseqr::type_id::create("seqr", this);
      drv  = l2_driver  ::type_id::create("drv",  this);
      mon  = l2_monitor ::type_id::create("mon",  this);

      if (!uvm_config_db#(cache_state_model)::get(this, "", "shared_state_model", state_model))
        state_model = cache_state_model::type_id::create("shared_state_model_l2", this);

      uvm_config_db#(cache_state_model)::set(this, "drv", "state_model", state_model);
      uvm_config_db#(cache_state_model)::set(this, "mon", "state_model", state_model);
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      drv.seq_item_port.connect(seqr.seq_item_export);
    endfunction
  endclass

  class cache_trace_mgr extends uvm_component;
    uvm_component_utils(cache_trace_mgr)

    uvm_analysis_imp #(cache_coh_item, cache_trace_mgr) trace_imp;
    int trace_fd;
    string trace_filename;
    int unsigned file_index;
    int unsigned max_bytes = 50_000_000;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      trace_imp = new("trace_imp", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      open_new_file();
    endfunction

    function void open_new_file();
      if (trace_fd) (trace_fd);
      trace_filename = ("cache_trace_%0d.log", file_index++);
      trace_fd = (trace_filename, "w");
      (trace_fd, "time,agent,core,txn,addr,state_before,state_after,sharers,data");
    endfunction

    function void write(cache_coh_item tr);
      string txn_str = tr.txn.name();
      (trace_fd, "%0t,%s,%0d,%s,0x%0h,%s,%s,%0d,0x%0h",
        , tr.src, tr.core_id, txn_str, tr.addr,
        tr.state_before.name(), tr.state_after.name(), tr.sharer_count, tr.data);
      if ((trace_fd) > max_bytes) begin
        (trace_fd);
        string zip_cmd = ("powershell -Command Compress-Archive -Force %s %s.zip", trace_filename, trace_filename);
        (zip_cmd);
        open_new_file();
      end
    endfunction

    function void final_phase(uvm_phase phase);
      if (trace_fd) (trace_fd);
    endfunction
  endclass

  class cache_scoreboard extends uvm_component;
    uvm_component_utils(cache_scoreboard)

    uvm_analysis_imp #(cache_coh_item, cache_scoreboard) l1_imp;
    uvm_analysis_imp #(cache_coh_item, cache_scoreboard) l2_imp;
    cache_state_model shared_state;
    cache_model_mgr   model_mgr;
    string modified_owner[string];

    function new(string name, uvm_component parent);
      super.new(name, parent);
      l1_imp = new("l1_imp", this);
      l2_imp = new("l2_imp", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(cache_state_model)::get(this, "", "shared_state_model", shared_state))
        shared_state = cache_state_model::type_id::create("scoreboard_state", this);
      model_mgr = cache_model_mgr::type_id::create("model_mgr", this);
      model_mgr.init(2);
      uvm_config_db#(cache_model_mgr)::set(this, "", "model_mgr", model_mgr);
    endfunction

    function void write(cache_coh_item tr);
      handle_event(tr, "L1");
    endfunction

    function void write_l2(cache_coh_item tr);
      handle_event(tr, "L2");
    endfunction

    function void handle_event(cache_coh_item tr, string agent);
      import cache_state_pkg::*;

      shared_state.observe(tr);

      if (agent == "L1") begin
        cache_model_pkg::txn_result_s res;
        if (tr.txn == TX_PR_RD)
          res = model_mgr.do_l1_cpu_read(tr.core_id, tr.addr);
        else if (tr.txn == TX_PR_WR)
          res = model_mgr.do_l1_cpu_write(tr.core_id, tr.addr, tr.data);
        if (tr.txn == TX_PR_RD && res.data !== tr.data)
          uvm_error("SCOREBOARD", ("Read mismatch @0x%0h exp=0x%0h got=0x%0h", tr.addr, res.data, tr.data));
      end else begin
        case (tr.txn)
          TX_BUS_RD : model_mgr.do_snoop(tr.addr, cache_model_pkg::S);
          TX_BUS_RDX,
          TX_BUS_INV: model_mgr.do_snoop(tr.addr, cache_model_pkg::M);
          TX_WB     : model_mgr.l2_model.process_flush(tr.addr);
          default   : ;
        endcase
      end

      if (tr.state_after == MESI_M) begin
        if (modified_owner.exists(tr.addr) && modified_owner[tr.addr] != agent)
          uvm_error("SCOREBOARD", ("Multiple Modified owners for 0x%0h: %s vs %s", tr.addr, modified_owner[tr.addr], agent));
        modified_owner[tr.addr] = agent;
      end else if (modified_owner.exists(tr.addr) && modified_owner[tr.addr] == agent) begin
        modified_owner.delete(tr.addr);
      end
    endfunction
  endclass

  class coh_state_checker extends uvm_component;
    uvm_component_utils(coh_state_checker)

    uvm_analysis_imp #(cache_coh_item, coh_state_checker) coh_imp;
    cache_state_model shared_state;
    mesi_state_e legal_trans[mesi_state_e][coh_txn_e];

    function new(string name, uvm_component parent);
      super.new(name, parent);
      coh_imp = new("coh_imp", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(cache_state_model)::get(this, "", "shared_state_model", shared_state))
        shared_state = cache_state_model::type_id::create("checker_state", this);
      init_table();
    endfunction

    function void init_table();
      legal_trans = '{default:'{default:MESI_I}};
      legal_trans[MESI_I][TX_PR_RD]   = MESI_E;
      legal_trans[MESI_I][TX_PR_WR]   = MESI_M;
      legal_trans[MESI_I][TX_BUS_RD]  = MESI_S;
      legal_trans[MESI_I][TX_BUS_RDX] = MESI_M;
      legal_trans[MESI_S][TX_PR_WR]   = MESI_M;
      legal_trans[MESI_S][TX_BUS_INV] = MESI_I;
      legal_trans[MESI_E][TX_PR_WR]   = MESI_M;
      legal_trans[MESI_E][TX_BUS_RD]  = MESI_S;
      legal_trans[MESI_M][TX_BUS_RD]  = MESI_O;
      legal_trans[MESI_M][TX_BUS_INV] = MESI_I;
      legal_trans[MESI_M][TX_WB]      = MESI_I;
      legal_trans[MESI_O][TX_PR_WR]   = MESI_M;
      legal_trans[MESI_O][TX_BUS_INV] = MESI_I;
    endfunction

    function void write(cache_coh_item tr);
      mesi_state_e prev = shared_state.get_state(tr.addr);
      mesi_state_e expected = legal_trans.exists(prev) && legal_trans[prev].exists(tr.txn)
                            ? legal_trans[prev][tr.txn] : prev;
      if (expected != tr.state_after)
        uvm_error("COH_STATE", ("Illegal transition @0x%0h: %s via %s -> %s (expected %s)",
                  tr.addr, prev.name(), tr.txn.name(), tr.state_after.name(), expected.name()));
      shared_state.observe(tr);
    endfunction
  endclass

  class coh_cov_sample extends uvm_object;
    uvm_object_utils(coh_cov_sample)
    cache_coh_item tr;
    mesi_state_e   l1_state_after;
    mesi_state_e   l2_state_after;
    int unsigned   sharer_count;
    bit            scoreboard_error;

    function new(string name = "coh_cov_sample");
      super.new(name);
    endfunction
  endclass

  class coh_coverage_collector extends uvm_subscriber #(cache_coh_item);
    uvm_component_utils(coh_coverage_collector)

    cache_state_model shared_state;
    cache_model_mgr   model_mgr;

    covergroup cg_protocol;
      state_prev : coverpoint tr.state_before;
      state_next : coverpoint tr.state_after;
      txn_cp     : coverpoint tr.txn;
      cross_prev_txn : cross state_prev, txn_cp;
      cross_transition : cross state_prev, txn_cp, state_next;
    endgroup

    covergroup cg_multilevel;
      l1_state : coverpoint sample.l1_state_after;
      l2_state : coverpoint sample.l2_state_after;
      sharers  : coverpoint sample.sharer_count {
        bins zero = {0};
        bins single = {1};
        bins multi = {[2:15]};
      }
      cross_l1_l2 : cross l1_state, l2_state;
    endgroup

    function new(string name, uvm_component parent);
      super.new(name, parent);
      cg_protocol = new;
      cg_multilevel = new;
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      uvm_config_db#(cache_state_model)::get(this, "", "shared_state_model", shared_state);
      uvm_config_db#(cache_model_mgr)::get(this, "", "model_mgr", model_mgr);
    endfunction

    function void write(cache_coh_item tr);
      cg_protocol.sample();
      coh_cov_sample sample = coh_cov_sample::type_id::create("sample");
      sample.tr = tr;
      if (model_mgr != null) begin
        sample.l1_state_after = shared_state.get_state(tr.addr);
        sample.l2_state_after = model_mgr.l2_model.get_state(tr.addr);
        sample.sharer_count   = model_mgr.sharer_count(tr.addr);
      end
      cg_multilevel.sample(sample);
    endfunction
  endclass

  class coh_error_coverage extends uvm_subscriber #(coh_cov_sample);
    uvm_component_utils(coh_error_coverage)

    covergroup cg_errors;
      cp_error : coverpoint sample.scoreboard_error;
      cp_txn   : coverpoint sample.tr.txn;
      cross_err_txn : cross cp_error, cp_txn;
    endgroup

    function new(string name, uvm_component parent);
      super.new(name, parent);
      cg_errors = new;
    endfunction

    function void write(coh_cov_sample sample);
      cg_errors.sample(sample);
    endfunction
  endclass

endpackage



