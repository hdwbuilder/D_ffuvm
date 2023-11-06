`timescale 1ns / 1ps
`include "uvm_macros.svh"
import uvm_pkg::*;

class transaction extends uvm_sequence_item;
  rand bit din;
  bit dout;
  
  function new(string path = "transaction");
    super.new(path);
  endfunction 
  
  `uvm_object_utils_begin(transaction)
  `uvm_field_int(din,UVM_DEFAULT);
  `uvm_field_int(dout,UVM_DEFAULT);
  `uvm_object_utils_end 
endclass 

class generator extends uvm_sequence#(transaction);
  `uvm_object_utils(generator)
  
  function new(string path = "generator");
    super.new(path);
  endfunction
  
  transaction t;
  
  virtual task body();
    t = transaction::type_id::create("t");
    repeat(10) begin 
      start_item(t);
      t.randomize();
      finish_item(t);
      `uvm_info("GEN",$sformatf(" Din %0d Dout %0d", t.din,t.dout),UVM_NONE);
    end   
  endtask 
  
endclass

class driver extends uvm_driver#(transaction);
  `uvm_component_utils(driver)
  
  virtual dff_if aif;
  transaction t;
  
  function new(string path = "driver", uvm_component parent = null);
    super.new(path,parent);
  endfunction 
  
  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    t = transaction::type_id::create("t");
    if(!uvm_config_db#(virtual dff_if)::get(this,"","aif",aif))
      `uvm_error("DRV", "Config_db error");
  endfunction 
  
  task reset_dut();
    aif.rst <= 1;
    aif.din <= 0;
    repeat(5) @(posedge aif.clk);
    aif.rst <= 0;
    `uvm_info("GEN","Reset complete",UVM_NONE);
  endtask 
  
  virtual task run_phase(uvm_phase phase);
    reset_dut();
    forever begin
      seq_item_port.get_next_item(t);
      aif.din <= t.din;
      `uvm_info("DRV",$sformatf(" Din %0d Dout %0d", t.din,t.dout),UVM_NONE);
      seq_item_port.item_done;
      repeat(2) @(posedge aif.clk);
    end 
  endtask 
endclass

class monitor extends uvm_monitor;
  `uvm_component_utils(monitor);
  
  virtual dff_if aif;
  transaction t;
  uvm_analysis_port#(transaction) sendr;
  
 function new(string path = "monitor", uvm_component parent = null);
    super.new(path,parent);
   sendr = new("sendr",this);
  endfunction 
    
   virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    t = transaction::type_id::create("t");
     if(!uvm_config_db#(virtual dff_if)::get(this,"","aif",aif))
       `uvm_error("MON", "Config_db error");
  endfunction 
  
 virtual task run_phase(uvm_phase phase);
    @(negedge aif.rst);
    forever begin 
      repeat(2) @(posedge aif.clk);
      t.din = aif.din;
      t.dout = aif.dout;
      `uvm_info("MON",$sformatf(" Din %0d Dout %0d", t.din,t.dout),UVM_NONE);
      sendr.write(t);
    end
  endtask 
endclass
       
class scoreboard extends uvm_scoreboard;
  `uvm_component_utils(scoreboard)
         
  transaction t; 
  uvm_analysis_imp #(transaction,scoreboard) recv;
         
  function new(string path = "scoreboard", uvm_component parent = null);
    super.new(path,parent);
   	recv = new("recv",this);
  endfunction 
  
  virtual function void build_phase(uvm_phase phase);
   super.build_phase(phase);
   t = transaction::type_id::create("t");
  endfunction 
  
  virtual function void write( input transaction tr);
    t = tr; 
    `uvm_info("SCO",$sformatf(" Din %0d Dout %0d", t.din,t.dout),UVM_NONE);
    if(t.din == t.dout)
      `uvm_info("SCO","Passed", UVM_NONE)
    else
      `uvm_info("SCO","Failed", UVM_NONE)
  endfunction 
endclass 
         
class agent extends uvm_agent;
  `uvm_component_utils(agent)

  driver d;
  monitor m;
  uvm_sequencer#(transaction) ack;
  
  function new(string path = "agent", uvm_component parent = null);
    super.new(path,parent);
  endfunction 
  
 virtual function void build_phase(uvm_phase phase);
   super.build_phase(phase);
   d = driver::type_id::create("d",this);
   m = monitor::type_id::create("m",this);
   ack = uvm_sequencer#(transaction)::type_id::create("ack",this);
  endfunction 
  
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    d.seq_item_port.connect(ack.seq_item_export);
  endfunction 
endclass 
      
    
class env extends uvm_env;
  `uvm_component_utils(env)
	
  agent a;
  scoreboard s;
  
  function new(string path = "env", uvm_component parent = null);
    super.new(path,parent);
  endfunction 
  
  virtual function void build_phase(uvm_phase phase);
   super.build_phase(phase);
    a = agent::type_id::create("a",this);
    s = scoreboard::type_id::create("s",this);
  endfunction 
 
  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    a.m.sendr.connect(s.recv);
  endfunction  
  
endclass 
    
class test extends uvm_test;
  `uvm_component_utils(test)
  
  function new(string path = "test", uvm_component parent = null);
    super.new(path,parent);
  endfunction   
    
  generator g;
  env e;
  
  virtual function void build_phase(uvm_phase phase);
   super.build_phase(phase);
    g = generator::type_id::create("g");
    e = env::type_id::create("e",this);
  endfunction 
  
  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    g.start(e.a.ack);
    #50;
    phase.drop_objection(this);
  endtask 
endclass 
    
module dff_tb();
	
  dff_if aif();
  
  dff dut (.clk(aif.clk),.rst(aif.rst),.din(aif.din),.dout(aif.dout));
  
  initial begin 
    aif.clk = 0;
    aif.rst = 0;
  end 

  always #10 aif.clk = ~aif.clk;
  
  initial begin
    uvm_config_db#(virtual dff_if)::set(null,"*","aif",aif);
    run_test("test");
  end 
  
  initial begin 
    $dumpfile("dump.vcd");
    $dumpvars;
  end 
endmodule 
    
    