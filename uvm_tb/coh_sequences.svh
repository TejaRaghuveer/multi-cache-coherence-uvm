//------------------------------------------------------------------------------
// coh_sequences.svh
//------------------------------------------------------------------------------
class coh_base_seq extends uvm_sequence #(cache_coh_item);
  uvm_object_utils(coh_base_seq)

  rand logic [31:0] base_addr;
  rand int unsigned span;

  constraint c_span { span inside {[0:15]}; }

  function new(string name = "coh_base_seq");
    super.new(name);
  endfunction

  function logic [31:0] addr_at(int unsigned idx);
    return base_addr + (idx << 6);
  endfunction

  task issue_read(logic [31:0] addr, bit force_shared = 0);
    cache_coh_item tr = cache_coh_item::type_id::create(("rd_%0h", addr));
    tr.txn  = force_shared ? cache_state_pkg::TX_BUS_RD : cache_state_pkg::TX_PR_RD;
    tr.addr = addr;
    start_item(tr);
    finish_item(tr);
  endtask

  task issue_write(logic [31:0] addr);
    cache_coh_item tr = cache_coh_item::type_id::create(("wr_%0h", addr));
    tr.txn  = cache_state_pkg::TX_PR_WR;
    tr.addr = addr;
    tr.data = ;
    start_item(tr);
    finish_item(tr);
  endtask

  task issue_invalidate(logic [31:0] addr);
    cache_coh_item tr = cache_coh_item::type_id::create(("inv_%0h", addr));
    tr.txn  = cache_state_pkg::TX_BUS_INV;
    tr.addr = addr;
    start_item(tr);
    finish_item(tr);
  endtask

  task issue_flush(logic [31:0] addr);
    cache_coh_item tr = cache_coh_item::type_id::create(("wb_%0h", addr));
    tr.txn  = cache_state_pkg::TX_WB;
    tr.addr = addr;
    start_item(tr);
    finish_item(tr);
  endtask
endclass

class coh_state_walk_seq extends coh_base_seq;
  uvm_object_utils(coh_state_walk_seq)

  task body();
    base_addr.randomize();
    issue_read(base_addr);
    issue_write(base_addr);
    issue_read(base_addr, 1);
    issue_invalidate(base_addr);
    issue_read(base_addr + 32'h40);
    issue_write(base_addr + 32'h40);
    issue_flush(base_addr + 32'h40);
  endtask
endclass

class coh_upgrade_seq extends coh_base_seq;
  uvm_object_utils(coh_upgrade_seq)

  task body();
    base_addr.randomize();
    issue_read(base_addr, 1);
    issue_write(base_addr);
    issue_invalidate(base_addr);
  endtask
endclass

class coh_conflict_seq extends coh_base_seq;
  uvm_object_utils(coh_conflict_seq)

  rand int unsigned iterations;
  constraint c_iter { iterations inside {[8:24]}; }

  task body();
    base_addr.randomize();
    repeat (iterations) begin
      logic [31:0] addr = addr_at((0, span));
      if ((0, 1)) issue_write(addr);
      else issue_read(addr);
      if ((0, 7) == 0) issue_invalidate(addr);
      if ((0, 11) == 0) issue_flush(addr);
    end
  endtask
endclass

class coh_random_seq extends coh_base_seq;
  uvm_object_utils(coh_random_seq)

  rand int unsigned num_ops;
  rand int unsigned write_ratio;

  constraint c_ops   { num_ops inside {[32:128]}; }
  constraint c_ratio { write_ratio inside {[0:100]}; }

  task body();
    repeat (num_ops) begin
      cache_coh_item tr = cache_coh_item::type_id::create("coh_tr");
      tr.randomize() with {
        txn dist {
          cache_state_pkg::TX_PR_RD   := 40,
          cache_state_pkg::TX_PR_WR   := write_ratio,
          cache_state_pkg::TX_BUS_RD  := 20,
          cache_state_pkg::TX_BUS_RDX := 10,
          cache_state_pkg::TX_BUS_INV := 5,
          cache_state_pkg::TX_WB      := 5
        };
        addr inside {[0:1023]};
      };
      start_item(tr);
      finish_item(tr);
    end
  endtask
endclass

class coh_full_transition_vseq extends uvm_sequence #(uvm_sequence_item);
  uvm_object_utils(coh_full_transition_vseq)

  cache_vseqr l1_seqr_h;
  cache_vseqr l2_seqr_h;
  rand int unsigned phase_reps;
  constraint c_phase { phase_reps inside {[1:3]}; }

  task body();
    repeat (phase_reps) begin
      coh_state_walk_seq l1_walk = coh_state_walk_seq::type_id::create("l1_walk");
      coh_state_walk_seq l2_walk = coh_state_walk_seq::type_id::create("l2_walk");
      coh_upgrade_seq    l1_up   = coh_upgrade_seq   ::type_id::create("l1_up");
      coh_conflict_seq   l2_conf = coh_conflict_seq  ::type_id::create("l2_conf");
      coh_random_seq     l1_rand = coh_random_seq    ::type_id::create("l1_rand");

      fork
        l1_walk.start(l1_seqr_h);
        l2_walk.start(l2_seqr_h);
      join

      fork
        l1_up.start(l1_seqr_h);
        l2_conf.start(l2_seqr_h);
        l1_rand.start(l1_seqr_h);
      join
    end
  endtask
endclass
