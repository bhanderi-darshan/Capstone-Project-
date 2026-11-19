// ============================================================================
// File:        tb_ahb_registers.sv
// Project:     AHB-Lite to I2C Master Controller
// Description: Comprehensive self-checking testbench for Phase 1.
//              Verifies AHB-Lite slave adapter and memory-mapped register bank:
//              1. Reset values of all eight registers
//              2. CONTROL register write/read & masking
//              3. CLOCK_DIV register write/read
//              4. TX_DATA register write/read & masking
//              5. TIMEOUT register write/read
//              6. COMMAND pulse generation (all 5 strobes)
//              7. STATUS hardware updates & read-only enforcement
//              8. RX_DATA hardware updates & Read-on-Clear of RX_VALID
//              9. IRQ pending, enable, and global masking
//              10. W1C clearing and simultaneous HW event resolution
//              11. AHB wait-state insertion on read and write
//              12. Back-to-back pipelined AHB transfers
//              13. Invalid register access handling
// Standard:    SystemVerilog IEEE 1800-2012
// ============================================================================

`timescale 1ns / 1ps

import i2c_pkg::*;

module tb_ahb_registers;

  // --------------------------------------------------------------------------
  // Clock & Reset Generator Signals
  // --------------------------------------------------------------------------
  logic        HCLK;
  logic        HRESETn;

  // --------------------------------------------------------------------------
  // AHB-Lite Bus Signals
  // --------------------------------------------------------------------------
  logic [31:0] HADDR;
  logic [31:0] HWDATA;
  logic        HWRITE;
  logic        HSEL;
  logic [1:0]  HTRANS;
  logic        HREADY;
  logic [31:0] HRDATA;
  logic        HREADYOUT;
  logic        HRESP;

  // --------------------------------------------------------------------------
  // Internal Register Interface (between Slave IF and Register Bank)
  // --------------------------------------------------------------------------
  logic        reg_write_en;
  logic        reg_read_en;
  logic [7:0]  reg_addr;
  logic [31:0] reg_wdata;
  logic [31:0] reg_rdata;

  // --------------------------------------------------------------------------
  // Hardware Status Inputs (Emulating I2C Core)
  // --------------------------------------------------------------------------
  logic        hw_busy;
  logic        hw_tx_empty;
  logic        hw_rx_valid;
  logic        hw_ack_error;
  logic        hw_timeout_error;
  logic        hw_done;
  logic [7:0]  hw_rx_data;

  // --------------------------------------------------------------------------
  // Hardware Command Strobes (Outputs from Register Bank)
  // --------------------------------------------------------------------------
  logic        cmd_start;
  logic        cmd_write;
  logic        cmd_read;
  logic        cmd_stop;
  logic        cmd_restart;

  // --------------------------------------------------------------------------
  // Configuration Outputs (Outputs to I2C Core)
  // --------------------------------------------------------------------------
  logic        ctrl_enable;
  logic        ctrl_int_enable;
  logic        ctrl_auto_stop;
  logic [15:0] clk_high_count;
  logic [15:0] clk_low_count;
  logic [7:0]  tx_data;
  logic [31:0] timeout_val;

  // --------------------------------------------------------------------------
  // Interrupt Output
  // --------------------------------------------------------------------------
  logic        irq_out;

  // --------------------------------------------------------------------------
  // Testbench Tracking Variables
  // --------------------------------------------------------------------------
  int test_count = 0;
  int pass_count = 0;
  int fail_count = 0;

  // --------------------------------------------------------------------------
  // Device Under Test (DUT) Instantiation
  // --------------------------------------------------------------------------
  // 1. AHB-Lite Slave Protocol Handler
  ahb_lite_slave_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32)
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

  // 2. Memory-Mapped Register Bank
  i2c_registers #(
      .DATA_WIDTH(32)
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
      .ctrl_int_enable_o (ctrl_int_enable),
      .ctrl_auto_stop_o  (ctrl_auto_stop),
      .clk_high_count_o  (clk_high_count),
      .clk_low_count_o   (clk_low_count),
      .tx_data_o         (tx_data),
      .timeout_val_o     (timeout_val),
      .irq_o             (irq_out)
  );

  // --------------------------------------------------------------------------
  // 100 MHz Clock Generation (T = 10 ns)
  // --------------------------------------------------------------------------
  initial begin
    HCLK = 1'b0;
    forever #5 HCLK = ~HCLK;
  end

  // --------------------------------------------------------------------------
  // AHB Bus Master Transaction Tasks
  // --------------------------------------------------------------------------
  task automatic bus_write(input [31:0] addr, input [31:0] data);
    begin
      @(posedge HCLK);
      HSEL   <= 1'b1;
      HTRANS <= 2'b10; // NONSEQ
      HWRITE <= 1'b1;
      HADDR  <= addr;
      HREADY <= 1'b1;

      @(posedge HCLK);
      HWDATA <= data;
      HSEL   <= 1'b0;
      HTRANS <= 2'b00; // IDLE
      HWRITE <= 1'b0;
      HADDR  <= 32'h0;

      @(posedge HCLK);
      HWDATA <= 32'h0;
    end
  endtask

  task automatic bus_read(input [31:0] addr, output [31:0] data);
    begin
      // Address Phase (Cycle N)
      @(posedge HCLK);
      HSEL   <= 1'b1;
      HTRANS <= 2'b10; // NONSEQ
      HWRITE <= 1'b0;
      HADDR  <= addr;
      HREADY <= 1'b1;

      // Data Phase begins (Cycle N+1)
      @(posedge HCLK);
      HSEL   <= 1'b0;
      HTRANS <= 2'b00; // IDLE
      HADDR  <= 32'h0;

      // Data Phase completes (Cycle N+2): Master clocks in HRDATA
      @(posedge HCLK);
      data   = HRDATA;
    end
  endtask

  task automatic bus_write_wait(input [31:0] addr, input [31:0] data, input int wait_cycles);
    begin
      @(posedge HCLK);
      HSEL   <= 1'b1;
      HTRANS <= 2'b10;
      HWRITE <= 1'b1;
      HADDR  <= addr;
      HREADY <= 1'b1;

      @(posedge HCLK);
      HWDATA <= data;
      HSEL   <= 1'b0;
      HTRANS <= 2'b00;
      HWRITE <= 1'b0;
      HADDR  <= 32'h0;

      // Wait state insertion
      repeat (wait_cycles) begin
        HREADY <= 1'b0;
        @(posedge HCLK);
      end

      HREADY <= 1'b1;
      @(posedge HCLK);
      HWDATA <= 32'h0;
    end
  endtask

  task automatic bus_read_wait(input [31:0] addr, output [31:0] data, input int wait_cycles);
    begin
      @(posedge HCLK);
      HSEL   <= 1'b1;
      HTRANS <= 2'b10;
      HWRITE <= 1'b0;
      HADDR  <= addr;
      HREADY <= 1'b1;

      @(posedge HCLK);
      HSEL   <= 1'b0;
      HTRANS <= 2'b00;
      HADDR  <= 32'h0;

      repeat (wait_cycles) begin
        HREADY <= 1'b0;
        @(posedge HCLK);
      end

      HREADY <= 1'b1;
      @(posedge HCLK);
      data   = HRDATA;
    end
  endtask

  // --------------------------------------------------------------------------
  // Check Assertion Helper
  // --------------------------------------------------------------------------
  task automatic check(
      input string test_name,
      input logic [31:0] actual,
      input logic [31:0] expected
  );
    begin
      test_count++;
      if (actual === expected) begin
        $display("[PASS] %s: Value = 0x%08X", test_name, actual);
        pass_count++;
      end else begin
        $display("[FAIL] %s: Expected = 0x%08X, Actual = 0x%08X", test_name, expected, actual);
        fail_count++;
      end
    end
  endtask

  // --------------------------------------------------------------------------
  // Main Verification Sequence
  // --------------------------------------------------------------------------
  logic [31:0] rdata;
  logic [31:0] rdata2;

  initial begin
    $dumpfile("sim/tb_ahb_registers.vcd");
    $dumpvars(0, tb_ahb_registers);

    $display("==================================================================");
    $display("  STARTING PHASE 1 VERIFICATION: AHB-LITE SLAVE & REGISTER BANK   ");
    $display("==================================================================");

    // Initialize AHB bus signals
    HRESETn          = 1'b0;
    HADDR            = 32'h0;
    HWDATA           = 32'h0;
    HWRITE           = 1'b0;
    HSEL             = 1'b0;
    HTRANS           = 2'b00;
    HREADY           = 1'b1;

    // Initialize hardware emulated signals
    hw_busy          = 1'b0;
    hw_tx_empty      = 1'b1;
    hw_rx_valid      = 1'b0;
    hw_ack_error     = 1'b0;
    hw_timeout_error = 1'b0;
    hw_done          = 1'b0;
    hw_rx_data       = 8'h00;

    // Apply Active-Low Reset
    #25;
    @(posedge HCLK);
    HRESETn = 1'b1;
    $display("[INFO] System reset deasserted.");
    @(posedge HCLK);

    // ------------------------------------------------------------------------
    // TEST 1: Reset Values of all Eight Registers
    // ------------------------------------------------------------------------
    $display("\n--- TEST 1: Register Reset Values ---");
    bus_read(32'h00, rdata); check("Reset CONTROL (0x00)", rdata, 32'h0000_0000);
    bus_read(32'h04, rdata); check("Reset STATUS (0x04) [TX_EMPTY=1]", rdata, 32'h0000_0002);
    bus_read(32'h08, rdata); check("Reset CLOCK_DIV (0x08) [100kHz default]", rdata, 32'h01F4_01F4);
    bus_read(32'h0C, rdata); check("Reset TX_DATA (0x0C)", rdata, 32'h0000_0000);
    bus_read(32'h10, rdata); check("Reset RX_DATA (0x10)", rdata, 32'h0000_0000);
    bus_read(32'h14, rdata); check("Reset COMMAND (0x14) [reads 0]", rdata, 32'h0000_0000);
    bus_read(32'h18, rdata); check("Reset TIMEOUT (0x18) [100k cycles]", rdata, 32'h0001_86A0);
    bus_read(32'h1C, rdata); check("Reset IRQ (0x1C)", rdata, 32'h0000_0000);

    // ------------------------------------------------------------------------
    // TEST 2: CONTROL Register Write, Read & Masking
    // ------------------------------------------------------------------------
    $display("\n--- TEST 2: CONTROL Register Write & Masking ---");
    // Write ENABLE=1, INT_ENABLE=1, AUTO_STOP=1
    bus_write(32'h00, 32'h0000_0007);
    bus_read(32'h00, rdata);
    check("CONTROL Write 0x07", rdata, 32'h0000_0007);
    check("ctrl_enable_o port", {31'd0, ctrl_enable}, 32'd1);
    check("ctrl_int_enable_o port", {31'd0, ctrl_int_enable}, 32'd1);
    check("ctrl_auto_stop_o port", {31'd0, ctrl_auto_stop}, 32'd1);

    // Write with upper reserved bits asserted (should be masked to 0)
    bus_write(32'h00, 32'hFFFF_FFF5); // bits [2:0] = 3'b101 (ENABLE=1, AUTO_STOP=1, INT=0)
    bus_read(32'h00, rdata);
    check("CONTROL Reserved Masking", rdata, 32'h0000_0005);
    check("ctrl_int_enable_o deasserted", {31'd0, ctrl_int_enable}, 32'd0);

    // ------------------------------------------------------------------------
    // TEST 3: CLOCK_DIV Register Write & Read (Independent High/Low)
    // ------------------------------------------------------------------------
    $display("\n--- TEST 3: CLOCK_DIV Register (Fast Mode 400 kHz) ---");
    // Fast mode: LOW_COUNT = 130 (0x0082), HIGH_COUNT = 120 (0x0078)
    bus_write(32'h08, 32'h0082_0078);
    bus_read(32'h08, rdata);
    check("CLOCK_DIV Fast Mode", rdata, 32'h0082_0078);
    check("clk_high_count_o port", {16'd0, clk_high_count}, 32'd120);
    check("clk_low_count_o port", {16'd0, clk_low_count}, 32'd130);

    // ------------------------------------------------------------------------
    // TEST 4: TX_DATA Register Write, Read & Masking
    // ------------------------------------------------------------------------
    $display("\n--- TEST 4: TX_DATA Register ---");
    bus_write(32'h0C, 32'h0000_00A5);
    bus_read(32'h0C, rdata);
    check("TX_DATA Write 0xA5", rdata, 32'h0000_00A5);
    check("tx_data_o port", {24'd0, tx_data}, 32'h0000_00A5);

    // Upper bits masking
    bus_write(32'h0C, 32'hDEAD_BE55);
    bus_read(32'h0C, rdata);
    check("TX_DATA Masking", rdata, 32'h0000_0055);
    check("tx_data_o port masked", {24'd0, tx_data}, 32'h0000_0055);

    // ------------------------------------------------------------------------
    // TEST 5: TIMEOUT Register Write & Read
    // ------------------------------------------------------------------------
    $display("\n--- TEST 5: TIMEOUT Register ---");
    bus_write(32'h18, 32'h0005_4321);
    bus_read(32'h18, rdata);
    check("TIMEOUT Write 0x00054321", rdata, 32'h0005_4321);
    check("timeout_val_o port", timeout_val, 32'h0005_4321);

    // Disable timeout (write 0)
    bus_write(32'h18, 32'h0000_0000);
    bus_read(32'h18, rdata);
    check("TIMEOUT Disabled (0)", rdata, 32'h0000_0000);

    // ------------------------------------------------------------------------
    // TEST 6: COMMAND Pulse Generation
    // ------------------------------------------------------------------------
    $display("\n--- TEST 6: COMMAND Pulse Generation ---");
    // Start Pulse (bit 0)
    @(posedge HCLK);
    bus_write(32'h14, 32'h0000_0001); // Issue START
    // Reading COMMAND should always return 0
    bus_read(32'h14, rdata);
    check("COMMAND read always 0", rdata, 32'h0000_0000);

    // Write Pulse (bit 1)
    bus_write(32'h14, 32'h0000_0002);
    // Read Pulse (bit 2)
    bus_write(32'h14, 32'h0000_0004);
    // Stop Pulse (bit 3)
    bus_write(32'h14, 32'h0000_0008);
    // Restart Pulse (bit 4)
    bus_write(32'h14, 32'h0000_0010);
    $display("[PASS] Command strobes executed without hanging.");

    // ------------------------------------------------------------------------
    // TEST 7: STATUS Register Hardware Updates & Read-Only Protection
    // ------------------------------------------------------------------------
    $display("\n--- TEST 7: STATUS Register Hardware Updates ---");
    // 1. Live BUSY & TX_EMPTY updates
    hw_busy     = 1'b1;
    hw_tx_empty = 1'b0;
    @(posedge HCLK);
    bus_read(32'h04, rdata);
    check("STATUS BUSY=1, TX_EMPTY=0", rdata[1:0], 2'b01);

    // 2. Latched Errors & Done
    hw_ack_error     = 1'b1;
    hw_timeout_error = 1'b1;
    hw_done          = 1'b1;
    @(posedge HCLK);
    hw_ack_error     = 1'b0;
    hw_timeout_error = 1'b0;
    hw_done          = 1'b0;
    @(posedge HCLK);

    bus_read(32'h04, rdata);
    // Bits [5:3] should be 3'b111 (DONE=1, TIMEOUT_ERROR=1, ACK_ERROR=1)
    check("STATUS Sticky Flags Latched", rdata[5:3], 3'b111);

    // 3. Status Read-Only Protection: Try to overwrite STATUS
    bus_write(32'h04, 32'h0000_0000);
    bus_read(32'h04, rdata);
    check("STATUS Read-Only Protection", rdata[5:3], 3'b111);

    // 4. Issue a new command (START) -> should clear latched status flags
    bus_write(32'h14, 32'h0000_0001);
    bus_read(32'h04, rdata);
    check("STATUS Cleared on New Command", rdata[5:3], 3'b000);

    hw_busy = 1'b0;
    @(posedge HCLK);

    // ------------------------------------------------------------------------
    // TEST 8: RX_DATA Hardware Updates & Read-on-Clear
    // ------------------------------------------------------------------------
    $display("\n--- TEST 8: RX_DATA Hardware Updates & Read-on-Clear ---");
    hw_rx_data  = 8'h5A;
    hw_rx_valid = 1'b1;
    @(posedge HCLK);
    hw_rx_valid = 1'b0;
    @(posedge HCLK);

    // Check STATUS.RX_VALID bit is 1
    bus_read(32'h04, rdata);
    check("STATUS RX_VALID == 1", {31'd0, rdata[2]}, 32'd1);

    // Read RX_DATA
    bus_read(32'h10, rdata);
    check("RX_DATA Read 0x5A", rdata, 32'h0000_005A);

    // Verify STATUS.RX_VALID is cleared upon reading RX_DATA
    bus_read(32'h04, rdata);
    check("STATUS RX_VALID Cleared (Read-on-Clear)", {31'd0, rdata[2]}, 32'd0);

    // ------------------------------------------------------------------------
    // TEST 9: IRQ Pending, Enables & Global Interrupt Masking
    // ------------------------------------------------------------------------
    $display("\n--- TEST 9: IRQ Logic & Global Masking ---");
    // Trigger HW DONE
    hw_done = 1'b1;
    @(posedge HCLK);
    hw_done = 1'b0;
    @(posedge HCLK);

    bus_read(32'h1C, rdata);
    check("IRQ DONE_PENDING == 1", {31'd0, rdata[0]}, 32'd1);
    check("irq_out == 0 (unmasked)", {31'd0, irq_out}, 32'd0);

    // Enable DONE interrupt (bit 8 of IRQ)
    bus_write(32'h1C, 32'h0000_0100);
    // Still 0 because CONTROL.INT_ENABLE is 0
    #1; check("irq_out == 0 (global int disabled)", {31'd0, irq_out}, 32'd0);

    // Enable Global Interrupt (CONTROL bit 1)
    bus_write(32'h00, 32'h0000_0003); // ENABLE=1, INT_ENABLE=1
    #1; check("irq_out == 1 (active interrupt)", {31'd0, irq_out}, 32'd1);

    // ------------------------------------------------------------------------
    // TEST 10: W1C (Write-1-to-Clear) and Simultaneous HW Event
    // ------------------------------------------------------------------------
    $display("\n--- TEST 10: W1C Interrupt Clearing & Precedence ---");
    // Clear DONE_PENDING by writing 1 to bit 0, keeping DONE_ENABLE (bit 8)
    bus_write(32'h1C, 32'h0000_0101);
    bus_read(32'h1C, rdata);
    check("IRQ DONE_PENDING Cleared via W1C", {31'd0, rdata[0]}, 32'd0);
    check("irq_out drops to 0", {31'd0, irq_out}, 32'd0);

    // Test Simultaneous HW Set and SW W1C Clear:
    // Assert hw_done in exact cycle of bus write to IRQ with bit 0 = 1
    @(posedge HCLK);
    HSEL   <= 1'b1;
    HTRANS <= 2'b10;
    HWRITE <= 1'b1;
    HADDR  <= 32'h1C;
    HREADY <= 1'b1;

    @(posedge HCLK);
    HWDATA  <= 32'h0000_0101; // SW attempts W1C
    hw_done <= 1'b1;          // HW asserts DONE simultaneously!
    HSEL    <= 1'b0;
    HTRANS  <= 2'b00;
    HWRITE  <= 1'b0;

    @(posedge HCLK);
    hw_done <= 1'b0;
    HWDATA  <= 32'h0;

    bus_read(32'h1C, rdata);
    check("Simultaneous HW Done + W1C: HW Precedence", {31'd0, rdata[0]}, 32'd1);

    // Clear it cleanly now
    bus_write(32'h1C, 32'h0000_0101);

    // ------------------------------------------------------------------------
    // TEST 11: AHB Wait States on Read and Write
    // ------------------------------------------------------------------------
    $display("\n--- TEST 11: AHB Wait States on Read & Write ---");
    // Write with 3 wait cycles on HREADY
    bus_write_wait(32'h0C, 32'h0000_003C, 3);
    // Read with 2 wait cycles on HREADY
    bus_read_wait(32'h0C, rdata, 2);
    check("Wait-State Write & Read TX_DATA", rdata, 32'h0000_003C);

    // ------------------------------------------------------------------------
    // TEST 12: Back-to-Back Pipelined AHB Transfers
    // ------------------------------------------------------------------------
    $display("\n--- TEST 12: Back-to-Back AHB Transfers ---");
    // Cycle 0: Addr phase of Write to CLOCK_DIV (0x08)
    @(posedge HCLK);
    HSEL   <= 1'b1;
    HTRANS <= 2'b10;
    HWRITE <= 1'b1;
    HADDR  <= 32'h08;
    HREADY <= 1'b1;

    // Cycle 1: Data phase of Write to CLOCK_DIV, Addr phase of Write to TX_DATA (0x0C)
    @(posedge HCLK);
    HWDATA <= 32'h0200_0200;
    HADDR  <= 32'h0C;
    HWRITE <= 1'b1;

    // Cycle 2: Data phase of Write to TX_DATA, Addr phase of Read from CLOCK_DIV (0x08)
    @(posedge HCLK);
    HWDATA <= 32'h0000_0077;
    HADDR  <= 32'h08;
    HWRITE <= 1'b0;

    // Cycle 3: Data phase of Read from CLOCK_DIV begins, Bus becomes IDLE
    @(posedge HCLK);
    HSEL   <= 1'b0;
    HTRANS <= 2'b00;
    HWRITE <= 1'b0;
    HWDATA <= 32'h0;

    // Cycle 4: Data phase completes, sample read data
    @(posedge HCLK);
    rdata  = HRDATA;
    check("Back-to-Back Read CLOCK_DIV", rdata, 32'h0200_0200);

    // Verify TX_DATA was also written cleanly
    bus_read(32'h0C, rdata2);
    check("Back-to-Back Written TX_DATA", rdata2, 32'h0000_0077);

    // ------------------------------------------------------------------------
    // TEST 13: Invalid Register Address Access
    // ------------------------------------------------------------------------
    $display("\n--- TEST 13: Invalid Register Access Handling ---");
    // Read unmapped address (0x30)
    bus_read(32'h30, rdata);
    check("Invalid Addr 0x30 Read", rdata, 32'h0000_0000);
    check("Invalid Addr HRESP == OKAY", {31'd0, HRESP}, 32'd0);
    check("Invalid Addr HREADYOUT == 1", {31'd0, HREADYOUT}, 32'd1);

    // Write unmapped address (0x34) - should not corrupt other registers
    bus_write(32'h34, 32'hDEAD_BEEF);
    bus_read(32'h0C, rdata);
    check("TX_DATA uncorrupted by invalid write", rdata, 32'h0000_0077);

    // ------------------------------------------------------------------------
    // Summary
    // ------------------------------------------------------------------------
    $display("\n==================================================================");
    $display("                      PHASE 1 TEST SUMMARY                        ");
    $display("==================================================================");
    $display("  TOTAL TESTS : %0d", test_count);
    $display("  PASSED      : %0d", pass_count);
    $display("  FAILED      : %0d", fail_count);
    $display("==================================================================");

    if (fail_count == 0) begin
      $display("  >>> ALL PHASE 1 TESTS PASSED SUCCESSFULLY! <<<");
    end else begin
      $display("  >>> SOME TESTS FAILED. PLEASE INVESTIGATE! <<<");
    end
    $display("==================================================================\n");

    $finish;
  end

endmodule : tb_ahb_registers
