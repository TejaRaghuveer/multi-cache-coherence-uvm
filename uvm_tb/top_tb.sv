	imescale 1ns/1ps
import uvm_pkg::*;
include "uvm_macros.svh"
import cache_state_pkg::*;
import cache_model_pkg::*;
import cache_pkg::*;

module top_tb;
  logic clk;
  logic rst_n;

  cache_if cache_l1_if(clk, rst_n);
  cache_if cache_l2_if(clk, rst_n);

  dut #(.ADDR_WIDTH(32), .DATA_WIDTH(64)) u_dut (
    .clk    (clk),
    .rst_n  (rst_n),
    .l1_port(cache_l1_if),
    .l2_port(cache_l2_if)
  );

  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  initial begin
    rst_n = 0;
    #100 rst_n = 1;
  end

  initial begin
    uvm_config_db#(virtual cache_if)::set(null, "uvm_test_top.env.l1.drv", "vif", cache_l1_if);
    uvm_config_db#(virtual cache_if)::set(null, "uvm_test_top.env.l1.mon", "vif", cache_l1_if);
    uvm_config_db#(virtual cache_if)::set(null, "uvm_test_top.env.l2.drv", "vif", cache_l2_if);
    uvm_config_db#(virtual cache_if)::set(null, "uvm_test_top.env.l2.mon", "vif", cache_l2_if);
  end

  initial begin
    run_test("cache_test");
  end
endmodule

module dut #(parameter ADDR_WIDTH = 32, DATA_WIDTH = 64)
  (input logic clk,
   input logic rst_n,
   cache_if #(ADDR_WIDTH, DATA_WIDTH) l1_port,
   cache_if #(ADDR_WIDTH, DATA_WIDTH) l2_port);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      l1_port.gnt   <= 0;
      l1_port.valid <= 0;
      l2_port.ready <= 0;
      l2_port.valid <= 0;
    end else begin
      l1_port.gnt   <= l1_port.req;
      l1_port.valid <= l1_port.req && !l1_port.we;
      l1_port.rdata <= l1_port.wdata;

      l2_port.ready <= l2_port.req;
      if (l2_port.req && !l2_port.we) begin
        l2_port.valid <= 1;
        l2_port.rdata <= l2_port.wdata;
      end else begin
        l2_port.valid <= 0;
      end
    end
  end
endmodule
