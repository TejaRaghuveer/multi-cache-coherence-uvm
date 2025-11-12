//------------------------------------------------------------------------------
// cache_model_mgr.sv
//------------------------------------------------------------------------------
include "uvm_macros.svh"
import uvm_pkg::*;
import cache_model_pkg::*;
include "functional_cache_model.sv"

class cache_model_mgr extends uvm_object;
  uvm_object_utils(cache_model_mgr)

  functional_cache_model l1_models[string];
  functional_cache_model l2_model;
  int unsigned num_cores;

  function new(string name = "cache_model_mgr");
    super.new(name);
  endfunction

  function void init(int unsigned num_cores_p);
    num_cores = num_cores_p;
    foreach (l1_models[k]) l1_models.delete(k);

    for (int i = 0; i < num_cores; i++) begin
      string key = ("L1_%0d", i);
      l1_models[key] = functional_cache_model::type_id::create(key);
      l1_models[key].configure(128, 4, 0);
    end

    l2_model = functional_cache_model::type_id::create("L2");
    l2_model.configure(512, 8, 1);
  endfunction

  function txn_result_s do_l1_cpu_read(int unsigned core_id, logic [31:0] addr);
    string key = ("L1_%0d", core_id);
    txn_result_s res = l1_models[key].process_cpu_read(addr);
    if (!res.hit) begin
      txn_result_s l2_res = l2_model.process_cpu_read(addr);
      l1_models[key].process_cpu_read(addr);
      res.data = l2_res.data;
    end
    return res;
  endfunction

  function txn_result_s do_l1_cpu_write(int unsigned core_id, logic [31:0] addr, logic [63:0] data);
    string key = ("L1_%0d", core_id);
    txn_result_s res = l1_models[key].process_cpu_write(addr, data);
    if (!res.hit) begin
      txn_result_s l2_res = l2_model.process_cpu_write(addr, data);
      l1_models[key].process_cpu_write(addr, data);
      res.issue_wb |= l2_res.issue_wb;
    end
    return res;
  endfunction

  function void do_snoop(logic [31:0] addr, mesi_e target_state);
    foreach (l1_models[key]) begin
      txn_result_s l1_res = l1_models[key].process_snoop(addr, target_state);
      if (l1_res.issue_wb)
        l2_model.process_cpu_write(addr, l1_res.data);
    end
    l2_model.process_snoop(addr, target_state);
  endfunction

  function int unsigned sharer_count(logic [31:0] addr);
    int unsigned count = 0;
    foreach (l1_models[key]) begin
      if (l1_models[key].is_sharer(addr))
        count++;
    end
    return count;
  endfunction
endclass
