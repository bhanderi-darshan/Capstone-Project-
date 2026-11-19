// ============================================================================
// File:        i2c_master_top.sv
// Project:     AHB-Lite to I2C Master Controller
// Description: Synthesizable top-level module integrating the AHB-Lite slave
//              protocol adapter, memory-mapped register bank, and I2C master
//              controller core with programmable clock generator and hardware
//              clock-stretching timeout.
// Standard:    SystemVerilog IEEE 1800-2012 (Synthesizable)
// ============================================================================

`timescale 1ns / 1ps

module i2c_master_top #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
)(
    // ------------------------------------------------------------------------
    // AHB-Lite System Clock and Reset
    // ------------------------------------------------------------------------
    input  logic                  HCLK,       // 100 MHz System Clock
    input  logic                  HRESETn,    // Active-Low System Reset

    // ------------------------------------------------------------------------
    // AHB-Lite Slave Bus Interface
    // ------------------------------------------------------------------------
    input  logic [ADDR_WIDTH-1:0] HADDR,      // Transfer address bus (word-aligned: [7:2] decoded)
    input  logic [DATA_WIDTH-1:0] HWDATA,     // Write data bus
    input  logic                  HWRITE,     // Transfer direction: 1 = Write, 0 = Read
    input  logic                  HSEL,       // Slave select (active HIGH)
    input  logic [1:0]            HTRANS,     // Transfer type: 00=IDLE, 01=BUSY, 10=NONSEQ, 11=SEQ
    input  logic                  HREADY,     // Global bus-ready signal from central AHB interconnect
                                              // (Monitors system-wide wait states; slave samples address phase
                                              //  only when HREADY == 1'b1 and holds data phase if HREADY == 1'b0)
    output logic [DATA_WIDTH-1:0] HRDATA,     // Read data bus
    output logic                  HREADYOUT,  // Slave ready output (always 1'b1 for zero wait-states)
    output logic                  HRESP,      // Transfer response: 0 = OKAY, 1 = ERROR (always OKAY)

    // ------------------------------------------------------------------------
    // System Interrupt Line
    // ------------------------------------------------------------------------
    output logic                  irq_o,      // Active-HIGH interrupt request to CPU/NVIC

    // ------------------------------------------------------------------------
    // Physical I2C Bus Interface (Open-Drain Bidirectional Pins)
    // ------------------------------------------------------------------------
    inout  wire                   scl_io,     // Serial Clock Line (Open-Drain, requires external pull-up)
    inout  wire                   sda_io      // Serial Data Line  (Open-Drain, requires external pull-up)
);

  // --------------------------------------------------------------------------
  // Address Decoding & Unsupported Access Handling Notes:
  // --------------------------------------------------------------------------
  // - Address decoding is performed by u_ahb_slave via {HADDR[7:2], 2'b00},
  //   mapping 32-bit aligned addresses to internal 8-bit offset reg_addr[7:0].
  // - Supported registers: 0x00 (CONTROL), 0x04 (STATUS), 0x08 (CLOCK_DIV),
  //   0x0C (TX_DATA), 0x10 (RX_DATA), 0x14 (COMMAND), 0x18 (TIMEOUT), 0x1C (IRQ).
  // - Unsupported/unmapped register addresses within the peripheral decode space
  //   (e.g., 0x20..0xFF) return 32'h00000000 on reads with HRESP = OKAY (0), and
  //   ignore writes without modifying internal state or corrupting registers.
  // --------------------------------------------------------------------------

  // --------------------------------------------------------------------------
  // Internal Interconnect Signals: AHB Slave -> Register Bank
  // --------------------------------------------------------------------------
  logic                  reg_write_en;
  logic                  reg_read_en;
  logic [7:0]            reg_addr;
  logic [DATA_WIDTH-1:0] reg_wdata;
  logic [DATA_WIDTH-1:0] reg_rdata;

  // --------------------------------------------------------------------------
  // Internal Interconnect Signals: Register Bank -> Master Core
  // --------------------------------------------------------------------------
  logic        cmd_start;
  logic        cmd_write;
  logic        cmd_read;
  logic        cmd_stop;
  logic        cmd_restart;
  logic        ctrl_enable;
  logic        ctrl_auto_stop;
  logic [15:0] clk_high_count;
  logic [15:0] clk_low_count;
  logic [7:0]  tx_data;
  logic [31:0] timeout_limit;

  // --------------------------------------------------------------------------
  // Internal Interconnect Signals: Master Core -> Register Bank
  // --------------------------------------------------------------------------
  logic        hw_busy;
  logic        hw_tx_empty;
  logic        hw_rx_valid;
  logic        hw_ack_error;
  logic        hw_timeout_error;
  logic        hw_done;
  logic [7:0]  hw_rx_data;

  // --------------------------------------------------------------------------
  // Physical Open-Drain Drive & Sampling Wires
  // --------------------------------------------------------------------------
  logic        scl_drive_low;
  logic        sda_drive_low;
  wire         scl_in;
  wire         sda_in;

  // --------------------------------------------------------------------------
  // Physical Open-Drain Driving & Tri-State Dual Implementation:
  // --------------------------------------------------------------------------
  // 1. Open-Drain Driving Semantics:
  //    - When drive_low is asserted (1'b1), pull line actively to GND (1'b0).
  //    - When drive_low is deasserted (1'b0), release line to High-Z (1'bz).
  //    - The controller NEVER actively drives the bus HIGH (no push-pull drive).
  //
  // 2. Mandatory External Pull-Up Resistors:
  //    - External physical pull-up resistors (Rp) to VDD are REQUIRED on both
  //      scl_io and sda_io lines:
  //      * Standard-mode (100 kHz): typically 4.7 kOhm (Cb <= 400 pF).
  //      * Fast-mode (400 kHz): typically 1.8 kOhm - 2.2 kOhm (tr <= 300 ns).
  //    - In simulation testbenches without physical pull-ups, pullup primitives
  //      must be instantiated: `pullup(scl_io); pullup(sda_io);`.
  //
  // 3. Dual ASIC / FPGA Target Compatibility:
  //    - FPGA Synthesis (e.g. AMD/Xilinx Vivado, Intel Quartus):
  //      Synthesizers automatically infer bidirectional IOBUF primitives:
  //      IOBUF u_buf (.O(scl_in), .IO(scl_io), .I(1'b0), .T(~scl_drive_low));
  //    - ASIC Synthesis (e.g. TSMC, GF, SkyWater 130nm):
  //      When integrating as a core macro before the chip pad ring, standard
  //      bidirectional I/O pad cells (e.g. PDUW0808CD / sky130_fd_io) map:
  //      PAD.out = 1'b0, PAD.oe = drive_low, PAD.in = core_in.
  // --------------------------------------------------------------------------
  assign scl_io = scl_drive_low ? 1'b0 : 1'bz;
  assign sda_io = sda_drive_low ? 1'b0 : 1'bz;

  // Sample physical bus line state back into master core synchronizers
  assign scl_in = scl_io;
  assign sda_in = sda_io;

  // --------------------------------------------------------------------------
  // Instance 1: AHB-Lite Slave Protocol Adapter
  // --------------------------------------------------------------------------
  ahb_lite_slave_if #(
      .ADDR_WIDTH (ADDR_WIDTH),
      .DATA_WIDTH (DATA_WIDTH)
  ) u_ahb_slave (
      .HCLK        (HCLK),
      .HRESETn     (HRESETn),
      .HADDR       (HADDR),
      .HWDATA      (HWDATA),
      .HWRITE      (HWRITE),
      .HSEL        (HSEL),
      .HTRANS      (HTRANS),
      .HREADY      (HREADY),
      .HRDATA      (HRDATA),
      .HREADYOUT   (HREADYOUT),
      .HRESP       (HRESP),
      .reg_write_en(reg_write_en),
      .reg_read_en (reg_read_en),
      .reg_addr    (reg_addr),
      .reg_wdata   (reg_wdata),
      .reg_rdata   (reg_rdata)
  );

  // --------------------------------------------------------------------------
  // Instance 2: Memory-Mapped Register Bank & Interrupt Logic
  // --------------------------------------------------------------------------
  i2c_registers #(
      .DATA_WIDTH (DATA_WIDTH)
  ) u_registers (
      .clk               (HCLK),
      .rst_n             (HRESETn),
      .reg_write_en      (reg_write_en),
      .reg_read_en       (reg_read_en),
      .reg_addr          (reg_addr),
      .reg_wdata         (reg_wdata),
      .reg_rdata         (reg_rdata),
      .hw_busy_i         (hw_busy),
      .hw_tx_empty_i     (hw_tx_empty),
      .hw_rx_valid_i     (hw_rx_valid),
      .hw_ack_error_i    (hw_ack_error),
      .hw_timeout_error_i(hw_timeout_error),
      .hw_done_i         (hw_done),
      .hw_rx_data_i      (hw_rx_data),
      .cmd_start_o       (cmd_start),
      .cmd_write_o       (cmd_write),
      .cmd_read_o        (cmd_read),
      .cmd_stop_o        (cmd_stop),
      .cmd_restart_o     (cmd_restart),
      .ctrl_enable_o     (ctrl_enable),
      .ctrl_int_enable_o (), // Gated internally in i2c_registers to form irq_o
      .ctrl_auto_stop_o  (ctrl_auto_stop),
      .clk_high_count_o  (clk_high_count),
      .clk_low_count_o   (clk_low_count),
      .tx_data_o         (tx_data),
      .timeout_val_o     (timeout_limit),
      .irq_o             (irq_o)
  );

  // --------------------------------------------------------------------------
  // Instance 3: I2C Master Controller Core
  // (Internally contains u_clock_gen and u_timeout)
  // --------------------------------------------------------------------------
  i2c_master u_master (
      .clk               (HCLK),
      .rst_n             (HRESETn),
      .cmd_start_i       (cmd_start),
      .cmd_write_i       (cmd_write),
      .cmd_read_i        (cmd_read),
      .cmd_stop_i        (cmd_stop),
      .cmd_restart_i     (cmd_restart),
      .ctrl_enable_i     (ctrl_enable),
      .ctrl_auto_stop_i  (ctrl_auto_stop),
      .clk_high_count_i  (clk_high_count),
      .clk_low_count_i   (clk_low_count),
      .timeout_limit_i   (timeout_limit),
      .tx_data_i         (tx_data),
      .hw_busy_o         (hw_busy),
      .hw_tx_empty_o     (hw_tx_empty),
      .hw_rx_valid_o     (hw_rx_valid),
      .hw_ack_error_o    (hw_ack_error),
      .hw_timeout_error_o(hw_timeout_error),
      .hw_done_o         (hw_done),
      .hw_rx_data_o      (hw_rx_data),
      .scl_in            (scl_in),
      .sda_in            (sda_in),
      .scl_drive_low_o   (scl_drive_low),
      .sda_drive_low_o   (sda_drive_low)
  );

endmodule : i2c_master_top
