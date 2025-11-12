//------------------------------------------------------------------------------
// cache_env_test.sv
//------------------------------------------------------------------------------
import uvm_pkg::*;
include "uvm_macros.svh"
import cache_state_pkg::*;
import cache_model_pkg::*;
import cache_pkg::*;

class cache_env extends uvm_env;
  uvm_component_utils(cache_env)

  l1_agent             l1;
  l2_agent             l2;
  cache_scoreboard     sb;
  coh_state_checker    state_chk;
  coh_coverage_collector cov_coll;
  coh_error_coverage   err_cov;
  cache_trace_mgr      trace_mgr;
  cache_state_model    shared_state_model;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    shared_state_model = cache_state_model::type_id::create("shared_state_model", this);

    uvm_config_db#(cache_state_model)::set(this, "l1", "shared_state_model", shared_state_model);
    uvm_config_db#(cache_state_model)::set(this, "l2", "shared_state_model", shared_state_model);
    uvm_config_db#(cache_state_model)::set(this, "sb", "shared_state_model", shared_state_model);
    uvm_config_db#(cache_state_model)::set(this, "state_chk", "shared_state_model", shared_state_model);
    uvm_config_db#(cache_state_model)::set(this, "cov_coll", "shared_state_model", shared_state_model);

    l1 = l1_agent            ::type_id::create("l1", this);
    l2 = l2_agent            ::type_id::create("l2", this);
    sb = cache_scoreboard    ::type_id::create("sb", this);
    state_chk = coh_state_checker::type_id::create("state_chk", this);
    cov_coll  = coh_coverage_collector::type_id::create("cov_coll", this);
    err_cov   = coh_error_coverage  ::type_id::create("err_cov", this);
    trace_mgr = cache_trace_mgr     ::type_id::create("trace_mgr", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    l1.mon.ap.connect(sb.l1_imp);
    l2.mon.ap.connect(sb.l2_imp);
    l1.mon.ap.connect(state_chk.coh_imp);
    l2.mon.ap.connect(state_chk.coh_imp);
    l1.mon.ap.connect(cov_coll.analysis_export);
    l2.mon.ap.connect(cov_coll.analysis_export);
    l1.mon.trace_ap.connect(trace_mgr.trace_imp);
    l2.mon.trace_ap.connect(trace_mgr.trace_imp);
  endfunction
endclass

class cache_test extends uvm_test;
  uvm_component_utils(cache_test)

  cache_env env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = cache_env::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    phase.raise_objection(this);

    coh_full_transition_vseq vseq = coh_full_transition_vseq::type_id::create("vseq");
    uvm_config_db#(cache_vseqr)::get(this, "env.l1", "seqr", vseq.l1_seqr_h);
    uvm_config_db#(cache_vseqr)::get(this, "env.l2", "seqr", vseq.l2_seqr_h);
    vseq.start(null);

    phase.drop_objection(this);
  endtask
endclass
