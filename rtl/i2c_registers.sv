// ============================================================================
// File:        i2c_registers.sv
// Project:     AHB-Lite to I2C Master Controller
// Description: Memory-mapped register bank for I2C Master Controller.
//              Contains 8 word-aligned 32-bit registers, command strobe logic,
//              status tracking, and W1C interrupt logic.
// Standard:    SystemVerilog IEEE 1800-2012 (Synthesizable)
// ============================================================================

`timescale 1ns / 1ps

import i2c_pkg::*;

module i2c_registers #(
    parameter int DATA_WIDTH = 32
)(
    input  logic                  clk,
    input  logic                  rst_n,

    // Bus Interface from AHB-Lite Slave Adapter
    input  logic                  reg_write_en,
    input  logic                  reg_read_en,
    input  logic [7:0]            reg_addr,
    input  logic [DATA_WIDTH-1:0] reg_wdata,
    output logic [DATA_WIDTH-1:0] reg_rdata,

    // Hardware Status Inputs from Core
    input  logic                  hw_busy_i,
    input  logic                  hw_tx_empty_i,
    input  logic                  hw_rx_valid_i,
    input  logic                  hw_ack_error_i,
    input  logic                  hw_timeout_error_i,
    input  logic                  hw_done_i,
    input  logic [7:0]            hw_rx_data_i,

    // Command Strobes to Core (active high, 1-cycle pulses)
    output logic                  cmd_start_o,
    output logic                  cmd_write_o,
    output logic                  cmd_read_o,
    output logic                  cmd_stop_o,
    output logic                  cmd_restart_o,

    // Configuration Outputs to Core
    output logic                  ctrl_enable_o,
    output logic                  ctrl_int_enable_o,
    output logic                  ctrl_auto_stop_o,
    output logic [15:0]           clk_high_count_o,
    output logic [15:0]           clk_low_count_o,
    output logic [7:0]            tx_data_o,
    output logic [31:0]           timeout_val_o,

    // Global Interrupt Line to System
    output logic                  irq_o
);

  // --------------------------------------------------------------------------
  // Internal Register Declarations
  // --------------------------------------------------------------------------
  // CONTROL Register (0x00)
  logic [2:0]  control_reg;

  // CLOCK_DIV Register (0x08)
  logic [31:0] clock_div_reg;

  // TX_DATA Register (0x0C)
  logic [7:0]  tx_data_reg;

  // RX_DATA Register (0x10)
  logic [7:0]  rx_data_reg;

  // TIMEOUT Register (0x18)
  logic [31:0] timeout_reg;

  // STATUS Register Internal Flags (0x04)
  logic        stat_rx_valid_q;
  logic        stat_ack_error_q;
  logic        stat_timeout_error_q;
  logic        stat_done_q;

  // IRQ Register Internal Flags & Enables (0x1C)
  logic        irq_done_pending_q;
  logic        irq_ack_error_pending_q;
  logic        irq_timeout_pending_q;

  logic        irq_done_enable_q;
  logic        irq_ack_error_enable_q;
  logic        irq_timeout_enable_q;

  // --------------------------------------------------------------------------
  // Command Strobes & Status Clearing Detection
  // --------------------------------------------------------------------------
  wire is_cmd_write = reg_write_en && (reg_addr == ADDR_COMMAND);

  // Generating 1-cycle command strobes
  assign cmd_start_o   = is_cmd_write && reg_wdata[CMD_START_BIT];
  assign cmd_write_o   = is_cmd_write && reg_wdata[CMD_WRITE_BIT];
  assign cmd_read_o    = is_cmd_write && reg_wdata[CMD_READ_BIT];
  assign cmd_stop_o    = is_cmd_write && reg_wdata[CMD_STOP_BIT];
  assign cmd_restart_o = is_cmd_write && reg_wdata[CMD_RESTART_BIT];

  // Writing any valid non-zero command clears sticky status indicators
  wire new_command_issued = is_cmd_write && (reg_wdata[4:0] != 5'd0);

  // Read of RX_DATA register clears RX_VALID
  wire rx_data_read = reg_read_en && (reg_addr == ADDR_RX_DATA);

  // --------------------------------------------------------------------------
  // Register Synchronous Sequential Logic
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // Default reset states
      control_reg             <= 3'b000;
      clock_div_reg           <= DEFAULT_CLOCK_DIV;
      tx_data_reg             <= 8'h00;
      rx_data_reg             <= 8'h00;
      timeout_reg             <= DEFAULT_TIMEOUT;

      // Status register reset
      stat_rx_valid_q         <= 1'b0;
      stat_ack_error_q        <= 1'b0;
      stat_timeout_error_q    <= 1'b0;
      stat_done_q             <= 1'b0;

      // IRQ register reset
      irq_done_pending_q      <= 1'b0;
      irq_ack_error_pending_q <= 1'b0;
      irq_timeout_pending_q   <= 1'b0;
      irq_done_enable_q       <= 1'b0;
      irq_ack_error_enable_q  <= 1'b0;
      irq_timeout_enable_q    <= 1'b0;
    end else begin
      // ----------------------------------------------------------------------
      // 1. Software Writes (AHB-Lite Write Phase)
      // ----------------------------------------------------------------------
      if (reg_write_en) begin
        case (reg_addr)
          ADDR_CONTROL: begin
            control_reg <= reg_wdata[2:0];
          end

          ADDR_CLOCK_DIV: begin
            clock_div_reg <= reg_wdata;
          end

          ADDR_TX_DATA: begin
            tx_data_reg <= reg_wdata[7:0];
          end

          ADDR_TIMEOUT: begin
            timeout_reg <= reg_wdata;
          end

          ADDR_IRQ: begin
            // Update interrupt enables
            irq_done_enable_q      <= reg_wdata[IRQ_DONE_ENABLE_BIT];
            irq_ack_error_enable_q <= reg_wdata[IRQ_ACK_ERROR_ENABLE_BIT];
            irq_timeout_enable_q   <= reg_wdata[IRQ_TIMEOUT_ENABLE_BIT];

            // W1C Clearing for Pending Flags (handled below with HW priority)
          end

          default: begin
            // Read-only or unused addresses: do nothing
          end
        endcase
      end

      // ----------------------------------------------------------------------
      // 2. Hardware Updates & Side-effects for RX_DATA & RX_VALID
      // ----------------------------------------------------------------------
      if (hw_rx_valid_i) begin
        rx_data_reg     <= hw_rx_data_i;
        stat_rx_valid_q <= 1'b1;
      end else if (rx_data_read || cmd_read_o) begin
        // Consumed by software read or new read command
        stat_rx_valid_q <= 1'b0;
      end

      // ----------------------------------------------------------------------
      // 3. Status Flags (ACK_ERROR, TIMEOUT_ERROR, DONE)
      // ----------------------------------------------------------------------
      // DONE Status
      if (hw_done_i) begin
        stat_done_q <= 1'b1;
      end else if (new_command_issued) begin
        stat_done_q <= 1'b0;
      end

      // ACK_ERROR Status
      if (hw_ack_error_i) begin
        stat_ack_error_q <= 1'b1;
      end else if (new_command_issued) begin
        stat_ack_error_q <= 1'b0;
      end

      // TIMEOUT_ERROR Status
      if (hw_timeout_error_i) begin
        stat_timeout_error_q <= 1'b1;
      end else if (new_command_issued) begin
        stat_timeout_error_q <= 1'b0;
      end

      // ----------------------------------------------------------------------
      // 4. IRQ Pending Flags with W1C and Hardware Precedence
      // ----------------------------------------------------------------------
      // DONE Pending Flag
      if (hw_done_i) begin
        irq_done_pending_q <= 1'b1;
      end else if (reg_write_en && (reg_addr == ADDR_IRQ) && reg_wdata[IRQ_DONE_PENDING_BIT]) begin
        irq_done_pending_q <= 1'b0; // W1C
      end

      // ACK Error Pending Flag
      if (hw_ack_error_i) begin
        irq_ack_error_pending_q <= 1'b1;
      end else if (reg_write_en && (reg_addr == ADDR_IRQ) && reg_wdata[IRQ_ACK_ERROR_PENDING_BIT]) begin
        irq_ack_error_pending_q <= 1'b0; // W1C
      end

      // Timeout Pending Flag
      if (hw_timeout_error_i) begin
        irq_timeout_pending_q <= 1'b1;
      end else if (reg_write_en && (reg_addr == ADDR_IRQ) && reg_wdata[IRQ_TIMEOUT_PENDING_BIT]) begin
        irq_timeout_pending_q <= 1'b0; // W1C
      end
    end
  end

  // --------------------------------------------------------------------------
  // Read Multiplexer (Combinational)
  // --------------------------------------------------------------------------
  always_comb begin
    case (reg_addr)
      ADDR_CONTROL: begin
        reg_rdata = {29'd0, control_reg};
      end

      ADDR_STATUS: begin
        reg_rdata = {
          26'd0,
          stat_done_q,
          stat_timeout_error_q,
          stat_ack_error_q,
          stat_rx_valid_q,
          hw_tx_empty_i,
          hw_busy_i
        };
      end

      ADDR_CLOCK_DIV: begin
        reg_rdata = clock_div_reg;
      end

      ADDR_TX_DATA: begin
        reg_rdata = {24'd0, tx_data_reg};
      end

      ADDR_RX_DATA: begin
        reg_rdata = {24'd0, rx_data_reg};
      end

      ADDR_COMMAND: begin
        // Command register is write-only; reading always returns 0
        reg_rdata = 32'h00000000;
      end

      ADDR_TIMEOUT: begin
        reg_rdata = timeout_reg;
      end

      ADDR_IRQ: begin
        reg_rdata = {
          21'd0,
          irq_timeout_enable_q,
          irq_ack_error_enable_q,
          irq_done_enable_q,
          5'd0,
          irq_timeout_pending_q,
          irq_ack_error_pending_q,
          irq_done_pending_q
        };
      end

      default: begin
        // Unmapped registers return zero
        reg_rdata = 32'h00000000;
      end
    endcase
  end

  // --------------------------------------------------------------------------
  // Configuration Output Assignments
  // --------------------------------------------------------------------------
  assign ctrl_enable_o     = control_reg[CTRL_ENABLE_BIT];
  assign ctrl_int_enable_o = control_reg[CTRL_INT_ENABLE_BIT];
  assign ctrl_auto_stop_o  = control_reg[CTRL_AUTO_STOP_BIT];

  assign clk_high_count_o  = clock_div_reg[15:0];
  assign clk_low_count_o   = clock_div_reg[31:16];

  assign tx_data_o         = tx_data_reg;
  assign timeout_val_o     = timeout_reg;

  // --------------------------------------------------------------------------
  // Interrupt Output Logic
  // --------------------------------------------------------------------------
  // Masked by CONTROL.INT_ENABLE and individual enables in IRQ register
  wire done_irq_active      = irq_done_pending_q && irq_done_enable_q;
  wire ack_error_irq_active = irq_ack_error_pending_q && irq_ack_error_enable_q;
  wire timeout_irq_active   = irq_timeout_pending_q && irq_timeout_enable_q;

  assign irq_o = ctrl_int_enable_o && (done_irq_active || ack_error_irq_active || timeout_irq_active);

endmodule : i2c_registers
