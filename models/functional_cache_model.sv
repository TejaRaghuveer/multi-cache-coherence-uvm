//------------------------------------------------------------------------------
// functional_cache_model.sv
//------------------------------------------------------------------------------
include "uvm_macros.svh"
import uvm_pkg::*;
import cache_model_pkg::*;

class functional_cache_model extends uvm_object;
  uvm_object_utils(functional_cache_model)

  rand string       name;
  rand int unsigned num_sets;
  rand int unsigned num_ways;
  bit               inclusive;

  protected line_s cache_mem   [][];
  protected logic [63:0] backing_store[string];

  function new(string name = "functional_cache_model");
    super.new(name);
  endfunction

  function void configure(int unsigned sets, int unsigned ways, bit inclusive_p);
    num_sets  = sets;
    num_ways  = ways;
    inclusive = inclusive_p;
    cache_mem = new[num_sets];
    foreach (cache_mem[s]) cache_mem[s] = new[num_ways];
  endfunction

  function void reset();
    foreach (cache_mem[s]) begin
      foreach (cache_mem[s][w]) cache_mem[s][w] = '{default:'0};
    end
    backing_store.delete();
  endfunction

  function txn_result_s process_cpu_read(logic [31:0] addr);
    txn_result_s res = '{default:0};
    int set = addr_to_set(addr);
    logic [31:0] tag = addr_to_tag(addr);
    int hit_way = find_hit(set, tag);

    if (hit_way != -1) begin
      line_s line = cache_mem[set][hit_way];
      res.hit       = 1;
      res.data      = line.data;
      res.new_state = (line.state inside {I, S}) ? S : line.state;
      cache_mem[set][hit_way].state = res.new_state;
    end else begin
      res.hit  = 0;
      res.data = fetch_from_memory(addr);
      perform_allocate(set, tag, res.data, S);
    end
    return res;
  endfunction

  function txn_result_s process_cpu_write(logic [31:0] addr, logic [63:0] data);
    txn_result_s res = '{default:0};
    int set = addr_to_set(addr);
    logic [31:0] tag = addr_to_tag(addr);
    int hit_way = find_hit(set, tag);

    if (hit_way != -1) begin
      cache_mem[set][hit_way].state = M;
      cache_mem[set][hit_way].data  = data;
      cache_mem[set][hit_way].dirty = 1;
      res.hit       = 1;
      res.new_state = M;
      res.data      = data;
    end else begin
      res.hit = 0;
      replace_line(set, tag, data, M, res.issue_wb);
      res.new_state = M;
      res.data      = data;
    end
    return res;
  endfunction

  function txn_result_s process_snoop(logic [31:0] addr, mesi_e target_state);
    txn_result_s res = '{default:0};
    int set = addr_to_set(addr);
    logic [31:0] tag = addr_to_tag(addr);
    int hit_way = find_hit(set, tag);
    if (hit_way == -1) return res;

    line_s line = cache_mem[set][hit_way];
    res.hit  = 1;
    res.data = line.data;

    unique case (target_state)
      S: begin
        if (line.state == M) begin
          cache_mem[set][hit_way].state = O;
          res.new_state = O;
          res.issue_wb  = 1;
        end else if (line.state == E) begin
          cache_mem[set][hit_way].state = S;
          res.new_state = S;
        end
      end
      M: begin
        res.new_state = I;
        res.issue_wb  = (line.state inside {M, O});
        cache_mem[set][hit_way] = '{default:'0};
      end
      default: ;
    endcase
    return res;
  endfunction

  function txn_result_s process_flush(logic [31:0] addr);
    txn_result_s res = '{default:0};
    int set = addr_to_set(addr);
    logic [31:0] tag = addr_to_tag(addr);
    int hit_way = find_hit(set, tag);
    if (hit_way != -1) begin
      line_s line = cache_mem[set][hit_way];
      res.hit      = 1;
      res.data     = line.data;
      res.issue_wb = line.dirty;
      cache_mem[set][hit_way] = '{default:'0};
    end
    return res;
  endfunction

  protected function int addr_to_set(logic [31:0] addr);
    return (addr >> 6) % num_sets;
  endfunction

  protected function logic [31:0] addr_to_tag(logic [31:0] addr);
    return addr >> (6 + (num_sets));
  endfunction

  protected function int find_hit(int set, logic [31:0] tag);
    foreach (cache_mem[set][w]) begin
      if (cache_mem[set][w].valid && cache_mem[set][w].tag == tag)
        return w;
    end
    return -1;
  endfunction

  protected function logic [63:0] fetch_from_memory(logic [31:0] addr);
    if (backing_store.exists(addr)) return backing_store[addr];
    backing_store[addr] = ;
    return backing_store[addr];
  endfunction

  protected function void perform_allocate(
      int set, logic [31:0] tag, logic [63:0] data, mesi_e state);
    bit issue_wb;
    replace_line(set, tag, data, state, issue_wb);
  endfunction

  protected function void replace_line(
      int set, logic [31:0] tag, logic [63:0] data,
      mesi_e state, output bit issue_wb);
    int victim = select_victim_way(set);
    line_s old = cache_mem[set][victim];
    if (old.valid && old.dirty) begin
      logic [31:0] old_addr = {old.tag, set[((set))-1:0], 6'b0};
      backing_store[old_addr] = old.data;
      issue_wb = 1;
    end else begin
      issue_wb = 0;
    end
    cache_mem[set][victim] = '{valid:1, state:state, tag:tag, data:data, dirty:(state == M)};
  endfunction

  protected function int select_victim_way(int set);
    return (0, num_ways-1);
  endfunction

  function int unsigned is_sharer(logic [31:0] addr);
    int set = addr_to_set(addr);
    logic [31:0] tag = addr_to_tag(addr);
    int hit_way = find_hit(set, tag);
    if (hit_way == -1) return 0;
    return (cache_mem[set][hit_way].state inside {S, O, E});
  endfunction

  function mesi_e get_state(logic [31:0] addr);
    int set = addr_to_set(addr);
    logic [31:0] tag = addr_to_tag(addr);
    int hit_way = find_hit(set, tag);
    if (hit_way == -1) return I;
    return cache_mem[set][hit_way].state;
  endfunction
endclass
