// ============================================================================
// File:        ahb_lite_slave_if.sv
// Project:     AHB-Lite to I2C Master Controller
// Description: AHB-Lite 32-bit Slave Protocol Adapter.
//              Handles pipelined Address and Data phases, wait states,
//              and translates AHB transfers into internal synchronous
//              register access control signals.
// Standard:    SystemVerilog IEEE 1800-2012 (Synthesizable)
// ============================================================================

`timescale 1ns / 1ps

module ahb_lite_slave_if #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
)(
    // AHB-Lite Global Signals
    input  logic                  HCLK,       // AHB System Clock (100 MHz)
    input  logic                  HRESETn,    // Active-Low Reset

    // AHB-Lite Bus Interface (Slave)
    input  logic [ADDR_WIDTH-1:0] HADDR,      // Transfer address
    input  logic [DATA_WIDTH-1:0] HWDATA,     // Write data bus
    input  logic                  HWRITE,     // 1 = Write, 0 = Read
    input  logic                  HSEL,       // Slave Select
    input  logic [1:0]            HTRANS,     // Transfer Type: 00=IDLE, 01=BUSY, 10=NONSEQ, 11=SEQ
    input  logic                  HREADY,     // Bus transfer ready from master/arbiter
    output logic [DATA_WIDTH-1:0] HRDATA,     // Read data bus
    output logic                  HREADYOUT,  // Slave ready output (always 1 for 0-wait-state)
    output logic                  HRESP,      // Transfer response: 0 = OKAY, 1 = ERROR

    // Internal Register Interface
    output logic                  reg_write_en, // 1-cycle active write strobe
    output logic                  reg_read_en,  // 1-cycle active read completion strobe
    output logic [7:0]            reg_addr,     // Register offset (lower 8-bit word aligned)
    output logic [DATA_WIDTH-1:0] reg_wdata,    // Register write data
    input  logic [DATA_WIDTH-1:0] reg_rdata     // Register read data from register bank
);

  // --------------------------------------------------------------------------
  // AHB-Lite Transfer Constants
  // --------------------------------------------------------------------------
  localparam logic [1:0] TRANS_IDLE   = 2'b00;
  localparam logic [1:0] TRANS_BUSY   = 2'b01;
  localparam logic [1:0] TRANS_NONSEQ = 2'b10;
  localparam logic [1:0] TRANS_SEQ    = 2'b11;

  localparam logic RESP_OKAY  = 1'b0;
  localparam logic RESP_ERROR = 1'b1;

  // --------------------------------------------------------------------------
  // Address Phase Detection & Registers
  // --------------------------------------------------------------------------
  // A transfer is valid if this slave is selected (HSEL), the previous transfer
  // is completed (HREADY), and the master initiates NONSEQ or SEQ transfer.
  logic ahb_trans_valid;
  assign ahb_trans_valid = HSEL && HREADY && (HTRANS == TRANS_NONSEQ || HTRANS == TRANS_SEQ);

  // Pipelining registers to hold address phase state into the data phase
  logic        valid_data_phase_q;
  logic        write_q;
  logic [7:0]  addr_q;

  always_ff @(posedge HCLK or negedge HRESETn) begin
    if (!HRESETn) begin
      valid_data_phase_q <= 1'b0;
      write_q            <= 1'b0;
      addr_q             <= 8'h00;
    end else if (HREADY) begin
      // Sample the address phase control when HREADY is high.
      // If HREADY is low (wait state), the current data phase is held.
      valid_data_phase_q <= ahb_trans_valid;
      write_q            <= HWRITE;
      addr_q             <= {HADDR[7:2], 2'b00}; // Word-align to 32-bit boundary
    end
  end

  // --------------------------------------------------------------------------
  // Data Phase & Internal Register Control
  // --------------------------------------------------------------------------
  // A register write occurs when we are in a valid write data phase and HREADY is high
  assign reg_write_en = valid_data_phase_q && write_q && HREADY;
  assign reg_wdata    = HWDATA;

  // A register read occurs when in a valid read data phase and HREADY is high
  assign reg_read_en  = valid_data_phase_q && !write_q && HREADY;
  assign reg_addr     = addr_q;

  // Read data multiplexer output:
  // Present the register bank's read data during the data phase of a read transfer.
  assign HRDATA = (valid_data_phase_q && !write_q) ? reg_rdata : {DATA_WIDTH{1'b0}};

  // --------------------------------------------------------------------------
  // AHB Slave Responses
  // --------------------------------------------------------------------------
  // This peripheral operates with zero wait states for register accesses.
  assign HREADYOUT = 1'b1;
  assign HRESP     = RESP_OKAY;

endmodule : ahb_lite_slave_if
