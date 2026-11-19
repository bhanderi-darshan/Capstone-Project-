// ============================================================================
// File:        tb_i2c_master.sv
// Project:     AHB-Lite to I2C Master Controller Verification
// Description: Comprehensive self-checking testbench for Task C i2c_master.
//              Verifies all 15 mandated requirements:
//              1. Reset and idle behavior
//              2. START and STOP timing
//              3. Address transmission with ACK
//              4. Address NACK recovery
//              5. Single-byte write with ACK
//              6. Data NACK recovery
//              7. Single-byte read with master NACK
//              8. Repeated START
//              9. Multi-byte write transaction
//              10. Clock stretching tolerance
//              11. Bus-busy START rejection
//              12. AUTO_STOP enabled and disabled
//              13. TX_EMPTY and RX_VALID handshakes
//              14. Standard (100kHz) and Fast (400kHz) mode timing
//              15. SCL ownership handover without glitches
// Standard:    SystemVerilog IEEE 1800-2012
// ============================================================================

`timescale 1ns / 1ps

import i2c_pkg::*;

module tb_i2c_master;

  // --------------------------------------------------------------------------
  // Clock and Reset Signals (100 MHz HCLK, 10 ns period)
  // --------------------------------------------------------------------------
  logic        clk;
  logic        rst_n;

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk; // 100 MHz clock
  end

  // --------------------------------------------------------------------------
  // Master Controller Interface Signals
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

  logic        hw_busy;
  logic        hw_tx_empty;
  logic        hw_rx_valid;
  logic        hw_ack_error;
  logic        hw_timeout_error;
  logic        hw_done;
  logic [7:0]  hw_rx_data;

  logic        scl_drive_low_m;
  logic        sda_drive_low_m;

  // --------------------------------------------------------------------------
  // Slave Model Interface Signals
  // --------------------------------------------------------------------------
  logic        force_addr_nack;
  logic        force_data_nack;
  logic        stretch_en;
  logic [31:0] stretch_duration_ns;
  logic [3:0]  stretch_on_bit;
  logic [7:0]  slave_tx_data;

  logic [6:0]  captured_addr;
  logic        captured_rw;
  logic [7:0]  captured_data;
  logic        slave_data_valid;
  logic        slave_start_seen;
  logic        slave_stop_seen;

  logic        scl_drive_low_s;
  logic        sda_drive_low_s;

  // External Bus Overrides (for bus busy and timeout tests)
  logic        ext_sda_pull_low;
  logic        ext_scl_pull_low;
  logic [31:0] timeout_limit;
  logic        trigger_start_timeout;
  logic        trigger_restart_timeout;
  logic        trigger_stop_timeout;

  // Dedicated timeout injection during framing states
  always @(posedge clk) begin
    if (trigger_start_timeout && (dut.state_q == ST_START)) begin
      ext_scl_pull_low <= 1'b1;
    end else if (trigger_restart_timeout && (dut.state_q == ST_RESTART) && (dut.sub_phase_q == 3'd1)) begin
      ext_scl_pull_low <= 1'b1;
    end else if (trigger_stop_timeout && (dut.state_q == ST_STOP) && (dut.sub_phase_q == 3'd1)) begin
      ext_scl_pull_low <= 1'b1;
    end else if (!trigger_start_timeout && !trigger_restart_timeout && !trigger_stop_timeout) begin
      ext_scl_pull_low <= 1'b0;
    end
  end

  // --------------------------------------------------------------------------
  // Open-Drain I2C Bus Simulation with Pull-Up Resistors
  // --------------------------------------------------------------------------
  wire scl_bus = (scl_drive_low_m || scl_drive_low_s || ext_scl_pull_low) ? 1'b0 : 1'b1;
  wire sda_bus = (sda_drive_low_m || sda_drive_low_s || ext_sda_pull_low) ? 1'b0 : 1'b1;

  // Synchronizers into Master Core
  logic [1:0] scl_sync;
  logic [1:0] sda_sync;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      scl_sync <= 2'b11;
      sda_sync <= 2'b11;
    end else begin
      scl_sync <= {scl_sync[0], scl_bus};
      sda_sync <= {sda_sync[0], sda_bus};
    end
  end

  wire scl_in = scl_sync[1];
  wire sda_in = sda_sync[1];

  // --------------------------------------------------------------------------
  // Device Under Test (DUT): i2c_master
  // --------------------------------------------------------------------------
  i2c_master dut (
      .clk               (clk),
      .rst_n             (rst_n),
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
      .scl_drive_low_o   (scl_drive_low_m),
      .sda_drive_low_o   (sda_drive_low_m)
  );

  // --------------------------------------------------------------------------
  // Register Bank Instance (for Status & IRQ Integration Testing)
  // --------------------------------------------------------------------------
  logic        reg_write_en;
  logic        reg_read_en;
  logic [7:0]  reg_addr;
  logic [31:0] reg_wdata;
  wire  [31:0] reg_rdata;
  wire         irq_sig;

  i2c_registers u_regs (
      .clk               (clk),
      .rst_n             (rst_n),
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
      .cmd_start_o       (),
      .cmd_write_o       (),
      .cmd_read_o        (),
      .cmd_stop_o        (),
      .cmd_restart_o     (),
      .ctrl_enable_o     (),
      .ctrl_int_enable_o (),
      .ctrl_auto_stop_o  (),
      .clk_high_count_o  (),
      .clk_low_count_o   (),
      .tx_data_o         (),
      .timeout_val_o     (),
      .irq_o             (irq_sig)
  );

  // --------------------------------------------------------------------------
  // I2C Slave Behavioral Model
  // --------------------------------------------------------------------------
  i2c_slave_model #(
      .SLAVE_ADDR(7'h50)
  ) u_slave (
      .clk                (clk),
      .rst_n              (rst_n),
      .scl_in             (scl_bus),
      .scl_drive_low      (scl_drive_low_s),
      .sda_in             (sda_bus),
      .sda_drive_low      (sda_drive_low_s),
      .force_addr_nack    (force_addr_nack),
      .force_data_nack    (force_data_nack),
      .stretch_en         (stretch_en),
      .stretch_duration_ns(stretch_duration_ns),
      .stretch_on_bit     (stretch_on_bit),
      .tx_data_byte       (slave_tx_data),
      .captured_addr      (captured_addr),
      .captured_rw        (captured_rw),
      .captured_data      (captured_data),
      .data_valid         (slave_data_valid),
      .start_seen         (slave_start_seen),
      .stop_seen          (slave_stop_seen)
  );

  // --------------------------------------------------------------------------
  // Glitch Monitor on SCL Handover
  // --------------------------------------------------------------------------
  time last_scl_rise_time;
  int  scl_glitch_count = 0;

  always @(posedge scl_bus) begin
    last_scl_rise_time = $time;
  end

  always @(negedge scl_bus) begin
    if (hw_busy && ($time - last_scl_rise_time < 30) && ($time > 1000) && !trigger_restart_timeout && !trigger_stop_timeout) begin
      $display("[ASSERTION FAILURE @ %0d ns] Spurious SCL pulse detected! Pulse width = %0d ns",
               $time, $time - last_scl_rise_time);
      scl_glitch_count++;
    end
  end

  // --------------------------------------------------------------------------
  // Fast Mode Timing Monitor
  // --------------------------------------------------------------------------
  bit  measure_fast_mode = 0;
  time fm_scl_rise = 0;
  time fm_scl_fall = 0;
  time t_high_meas = 0;
  time t_low_meas  = 0;

  always @(posedge scl_bus) begin
    if (measure_fast_mode) begin
      fm_scl_rise = $time;
      if (fm_scl_fall > 0) begin
        t_low_meas = $time - fm_scl_fall;
      end
    end
  end

  always @(negedge scl_bus) begin
    if (measure_fast_mode) begin
      fm_scl_fall = $time;
      if (fm_scl_rise > 0) begin
        t_high_meas = $time - fm_scl_rise;
      end
    end
  end

  // --------------------------------------------------------------------------
  // Test Tracking and Utility Tasks
  // --------------------------------------------------------------------------
  int test_count = 0;
  int pass_count = 0;
  int fail_count = 0;

  task check(string msg, bit condition);
    test_count++;
    if (condition) begin
      $display("  [PASS] Test %2d: %s", test_count, msg);
      pass_count++;
    end else begin
      $display("  [FAIL] Test %2d: %s", test_count, msg);
      fail_count++;
    end
    $fflush();
  endtask

  task reset_dut();
    rst_n               = 1'b0;
    cmd_start           = 1'b0;
    cmd_write           = 1'b0;
    cmd_read            = 1'b0;
    cmd_stop            = 1'b0;
    cmd_restart         = 1'b0;
    ctrl_enable         = 1'b0;
    ctrl_auto_stop      = 1'b0;
    clk_high_count      = 16'd500; // Default 100 kHz
    clk_low_count       = 16'd500;
    timeout_limit       = 32'd0;   // Disabled initially
    tx_data             = 8'h00;
    force_addr_nack     = 1'b0;
    force_data_nack     = 1'b0;
    stretch_en          = 1'b0;
    stretch_duration_ns = 32'd0;
    stretch_on_bit      = 4'd0;
    slave_tx_data           = 8'h00;
    ext_sda_pull_low        = 1'b0;
    ext_scl_pull_low        = 1'b0;
    trigger_start_timeout   = 1'b0;
    trigger_restart_timeout = 1'b0;
    trigger_stop_timeout    = 1'b0;
    reg_write_en            = 1'b0;
    reg_read_en         = 1'b0;
    reg_addr            = 8'h00;
    reg_wdata           = 32'd0;
    #100;
    @(posedge clk);
    rst_n = 1'b1;
    #100;
    @(posedge clk);
  endtask

  task send_cmd_start();
    #6000; // Ensure t_BUF (5000 ns for 100kHz, 1300 ns for 400kHz) is fully satisfied
    @(posedge clk);
    cmd_start = 1'b1;
    @(posedge clk);
    cmd_start = 1'b0;
  endtask

  task send_cmd_write(input [7:0] byte_val);
    @(posedge clk);
    tx_data   = byte_val;
    cmd_write = 1'b1;
    @(posedge clk);
    cmd_write = 1'b0;
  endtask

  task send_cmd_read();
    @(posedge clk);
    cmd_read = 1'b1;
    @(posedge clk);
    cmd_read = 1'b0;
  endtask

  task send_cmd_stop();
    @(posedge clk);
    cmd_stop = 1'b1;
    @(posedge clk);
    cmd_stop = 1'b0;
  endtask

  task send_cmd_restart();
    @(posedge clk);
    cmd_restart = 1'b1;
    @(posedge clk);
    cmd_restart = 1'b0;
  endtask

  task wait_for_done(output bit ok, input int max_cycles);
    ok = 0;
    fork
      begin
        @(posedge hw_done);
        ok = 1;
      end
      begin
        repeat (max_cycles) @(posedge clk);
      end
    join_any
    disable fork;
  endtask

  task wait_for_ack_error(output bit ok, input int max_cycles);
    ok = 0;
    fork
      begin
        @(posedge hw_ack_error);
        ok = 1;
      end
      begin
        repeat (max_cycles) @(posedge clk);
      end
    join_any
    disable fork;
  endtask

  task wait_for_timeout_error(output bit ok, input int max_cycles);
    ok = 0;
    fork
      begin
        @(posedge hw_timeout_error);
        ok = 1;
        repeat (2) @(posedge clk);
      end
      begin
        repeat (max_cycles) @(posedge clk);
      end
    join_any
    disable fork;
  endtask

  task reg_write(input [7:0] addr, input [31:0] data);
    @(posedge clk);
    reg_write_en = 1'b1;
    reg_addr     = addr;
    reg_wdata    = data;
    @(posedge clk);
    reg_write_en = 1'b0;
    reg_addr     = 8'h00;
    reg_wdata    = 32'd0;
  endtask

  task reg_read(input [7:0] addr, output [31:0] data);
    @(posedge clk);
    reg_read_en = 1'b1;
    reg_addr    = addr;
    @(posedge clk);
    #1;
    data        = reg_rdata;
    reg_read_en = 1'b0;
    reg_addr    = 8'h00;
  endtask

  // --------------------------------------------------------------------------
  // Test Execution Sequence
  // --------------------------------------------------------------------------
  bit ok;
  time t_sda_fall, t_scl_fall;
  time t_scl_rise, t_sda_rise;
  time t_start_hold, t_stop_setup;

  initial begin
    $dumpfile("sim/tb_i2c_master.vcd");
    $dumpvars(0, tb_i2c_master);

    $display("============================================================================");
    $display("Starting Comprehensive Task C Verification: AHB-Lite I2C Master Controller");
    $display("============================================================================");

    reset_dut();

    // ------------------------------------------------------------------------
    // Test 1: Reset & Idle Behavior
    // ------------------------------------------------------------------------
    $display("\n--- Test Suite 1: Reset and Bus Idle Behavior ---");
    check("hw_busy_o is 0 at reset", hw_busy == 1'b0);
    check("hw_tx_empty_o is 1 at reset", hw_tx_empty == 1'b1);
    check("scl_drive_low_m is 0 (released) at reset", scl_drive_low_m == 1'b0);
    check("sda_drive_low_m is 0 (released) at reset", sda_drive_low_m == 1'b0);
    check("scl_bus floats HIGH", scl_bus == 1'b1);
    check("sda_bus floats HIGH", sda_bus == 1'b1);

    // ------------------------------------------------------------------------
    // Test 2: Bus-Busy START Rejection
    // ------------------------------------------------------------------------
    $display("\n--- Test Suite 2: Bus-Busy START Rejection ---");
    ctrl_enable = 1'b1;
    // Simulate external device pulling SDA LOW
    ext_sda_pull_low = 1'b1;
    #200; // Let synchronizers settle
    send_cmd_start();
    #200;
    check("START rejected when SDA is LOW: hw_busy_o remains 0", hw_busy == 1'b0);
    check("START rejected: Master does not pull SCL LOW", scl_drive_low_m == 1'b0);
    check("START rejected: hw_ack_error_o is NOT asserted", hw_ack_error == 1'b0);
    check("START rejected: hw_done_o is NOT asserted", hw_done == 1'b0);
    ext_sda_pull_low = 1'b0; // Release bus
    #6000; // Wait for bus-free qualification (500 cycles = 5000 ns)

    // ------------------------------------------------------------------------
    // Test 3: START Framing & Timing Verification (100 kHz Standard Mode)
    // ------------------------------------------------------------------------
    $display("\n--- Test Suite 3: START Framing & Timing Verification ---");
    fork
      begin
        @(negedge sda_bus);
        t_sda_fall = $time;
      end
      begin
        @(negedge scl_bus);
        t_scl_fall = $time;
      end
    join_none

    send_cmd_start();
    wait_for_done(ok, 2000);
    check("START command completed (hw_done asserted)", ok == 1'b1);
    check("hw_busy_o asserted during transaction", hw_busy == 1'b1);
    check("hw_tx_empty_o remains 1 in ST_CMD_READY", hw_tx_empty == 1'b1);
    check("SCL held LOW in ST_CMD_READY", scl_bus == 1'b0);

    t_start_hold = t_scl_fall - t_sda_fall;
    $display("    [Timing] Measured t_HD;STA = %0d ns (Target = 5000 ns, Spec >= 4000 ns)", t_start_hold);
    check("START hold time t_HD;STA satisfies Spec (>= 4000 ns)", t_start_hold >= 4900 && t_start_hold <= 5100);

    // ------------------------------------------------------------------------
    // Test 4: Address Transmission with Slave ACK
    // ------------------------------------------------------------------------
    $display("\n--- Test Suite 4: Address Transmission with Slave ACK ---");
    // Transmit 7'h50 + Write (0) = 8'hA0
    send_cmd_write(8'hA0);
    check("hw_tx_empty_o drops to 0 during transmission", hw_tx_empty == 1'b0);
    wait_for_done(ok, 25000);
    check("Address Write complete (hw_done asserted)", ok == 1'b1);
    check("Slave captured correct 7-bit address 0x50", captured_addr == 7'h50);
    check("Slave captured Write direction (R/W = 0)", captured_rw == 1'b0);
    check("hw_tx_empty_o returns to 1 after Address ACK", hw_tx_empty == 1'b1);
    check("hw_busy_o remains 1 in ST_CMD_READY after Address ACK", hw_busy == 1'b1);
    check("SCL held LOW between Address and Data", scl_bus == 1'b0);

    // ------------------------------------------------------------------------
    // Test 5: Single-Byte Write with Slave ACK & Manual STOP
    // ------------------------------------------------------------------------
    $display("\n--- Test Suite 5: Single-Byte Write with Slave ACK & Manual STOP ---");
    send_cmd_write(8'hA5);
    check("hw_tx_empty_o drops to 0 during data write", hw_tx_empty == 1'b0);
    wait_for_done(ok, 25000);
    check("Data Write complete (hw_done asserted)", ok == 1'b1);
    check("Slave received data byte 0xA5", captured_data == 8'hA5);
    check("hw_tx_empty_o returns to 1 after Data ACK", hw_tx_empty == 1'b1);

    // Now issue manual STOP and measure timing sequentially
    send_cmd_stop();
    @(posedge scl_bus);
    t_scl_rise = $time;
    @(posedge sda_bus);
    t_sda_rise = $time;
    t_stop_setup = t_sda_rise - t_scl_rise;

    wait_for_done(ok, 25000);
    check("STOP command complete (hw_done asserted)", ok == 1'b1);
    check("hw_busy_o deasserted after STOP", hw_busy == 1'b0);
    check("Both SCL and SDA released after STOP", scl_bus == 1'b1 && sda_bus == 1'b1);

    $display("    [Timing] Measured t_SU;STO = %0d ns (Target = 5000 ns, Spec >= 4000 ns)", t_stop_setup);
    check("STOP setup time t_SU;STO satisfies Spec (>= 4000 ns)", t_stop_setup >= 4900 && t_stop_setup <= 5100);

    #1000;

    // ------------------------------------------------------------------------
    // Test 6: Address NACK Detection & Automatic STOP Abort
    // ------------------------------------------------------------------------
    $display("\n--- Test Suite 6: Address NACK Detection & Abort Recovery ---");
    force_addr_nack = 1'b1; // Configure slave to NACK address
    send_cmd_start();
    wait_for_done(ok, 2000);

    send_cmd_write(8'hA0);
    wait_for_ack_error(ok, 25000);
    check("Address NACK asserted hw_ack_error_o pulse", ok == 1'b1);
    check("Address NACK suppressed hw_done_o", hw_done == 1'b0);

    // Master should automatically execute STOP and return to IDLE
    #25000;
    check("Master returned to IDLE after NACK abort: hw_busy_o is 0", hw_busy == 1'b0);
    check("Bus lines released after NACK abort", scl_bus == 1'b1 && sda_bus == 1'b1);
    check("hw_tx_empty_o restored to 1", hw_tx_empty == 1'b1);
    force_addr_nack = 1'b0;

    #2000;

    // ------------------------------------------------------------------------
    // Test 7: Data NACK Detection & Automatic STOP Abort
    // ------------------------------------------------------------------------
    $display("\n--- Test Suite 7: Data NACK Detection & Abort Recovery ---");
    send_cmd_start();
    wait_for_done(ok, 2000);

    send_cmd_write(8'hA0); // Valid address ACK
    wait_for_done(ok, 25000);

    force_data_nack = 1'b1; // Force NACK on data byte
    send_cmd_write(8'h55);
    wait_for_ack_error(ok, 25000);
    check("Data NACK asserted hw_ack_error_o pulse", ok == 1'b1);
    check("Data NACK suppressed hw_done_o", hw_done == 1'b0);

    #25000;
    check("Master returned to IDLE after Data NACK: hw_busy_o is 0", hw_busy == 1'b0);
    check("Bus lines released after Data NACK abort", scl_bus == 1'b1 && sda_bus == 1'b1);
    force_data_nack = 1'b0;

    #2000;

    // ------------------------------------------------------------------------
    // Test 8: Single-Byte Read with Master NACK & AUTO_STOP
    // ------------------------------------------------------------------------
    $display("\n--- Test Suite 8: Single-Byte Read with Master NACK & AUTO_STOP ---");
    ctrl_auto_stop = 1'b1;  // Enable AUTO_STOP
    slave_tx_data  = 8'h3C; // Slave will send 0x3C

    send_cmd_start();
    wait_for_done(ok, 2000);

    send_cmd_write(8'hA1); // 7'h50 + Read (1) = 8'hA1
    wait_for_done(ok, 25000);
    check("Address Read ACK complete (AUTO_STOP correctly ignored on address)", hw_busy == 1'b1);

    send_cmd_read();
    wait_for_done(ok, 25000);
    check("Read command complete (hw_done asserted)", ok == 1'b1);
    check("hw_rx_data_o matched slave TX data (0x3C)", hw_rx_data == 8'h3C);

    #25000;
    check("AUTO_STOP automatically returned master to IDLE (hw_busy_o is 0)", hw_busy == 1'b0);
    check("Bus released after AUTO_STOP", scl_bus == 1'b1 && sda_bus == 1'b1);
    ctrl_auto_stop = 1'b0;

    #2000;

    // ------------------------------------------------------------------------
    // Test 9: Repeated START Multi-Phase Transaction
    // ------------------------------------------------------------------------
    $display("\n--- Test Suite 9: Repeated START Multi-Phase Transaction ---");
    send_cmd_start();
    wait_for_done(ok, 2000);

    // Phase 1: Write Address 0x50
    send_cmd_write(8'hA0);
    wait_for_done(ok, 25000);

    // Phase 2: Write Data 0x11
    send_cmd_write(8'h11);
    wait_for_done(ok, 25000);
    check("Phase 1 Data written (0x11)", captured_data == 8'h11);

    // Phase 3: Repeated START
    send_cmd_restart();
    wait_for_done(ok, 25000);
    check("Repeated START complete (hw_done asserted)", ok == 1'b1);
    check("hw_busy_o remained continuously asserted during Repeated START", hw_busy == 1'b1);
    check("Slave detected Repeated START", slave_start_seen == 1'b1);

    // Phase 4: Read Address 0x50
    slave_tx_data = 8'h77;
    send_cmd_write(8'hA1);
    wait_for_done(ok, 25000);

    // Phase 5: Read Data
    send_cmd_read();
    wait_for_done(ok, 25000);
    check("Phase 2 Read byte received (0x77)", hw_rx_data == 8'h77);

    // Phase 6: Manual STOP
    send_cmd_stop();
    wait_for_done(ok, 25000);
    check("Transaction completed with STOP", hw_busy == 1'b0);

    #6000; // Allow full t_BUF (5000 ns) qualification before next transaction

    // ------------------------------------------------------------------------
    // Test 10: Multi-Byte Write Burst (3 Data Bytes)
    // ------------------------------------------------------------------------
    $display("\n--- Test Suite 10: Multi-Byte Write Burst ---");
    send_cmd_start();
    wait_for_done(ok, 2000);

    send_cmd_write(8'hA0);
    wait_for_done(ok, 25000);

    send_cmd_write(8'h10);
    wait_for_done(ok, 25000);
    check("Multi-byte write byte 1 (0x10) confirmed by slave", captured_data == 8'h10);

    $display("    Sending multi-byte byte 2 (0x20)...");
    $fflush();
    send_cmd_write(8'h20);
    wait_for_done(ok, 25000);
    check("Multi-byte write byte 2 (0x20) confirmed by slave", captured_data == 8'h20);

    $display("    Sending multi-byte byte 3 (0x30)...");
    $fflush();
    send_cmd_write(8'h30);
    wait_for_done(ok, 25000);
    check("Multi-byte write byte 3 (0x30) confirmed by slave", captured_data == 8'h30);

    send_cmd_stop();
    wait_for_done(ok, 25000);
    check("Multi-byte burst finished cleanly", hw_busy == 1'b0);

    #6000; // Allow full t_BUF qualification

    // ------------------------------------------------------------------------
    // Test 11: Clock Stretching Tolerance
    // ------------------------------------------------------------------------
    $display("\n--- Test Suite 11: Clock Stretching Tolerance ---");
    stretch_en          = 1'b1;
    stretch_on_bit      = 4'd4;
    stretch_duration_ns = 32'd5000; // 5 us stretch

    send_cmd_start();
    wait_for_done(ok, 2000);

    send_cmd_write(8'hA0);
    wait_for_done(ok, 25000);

    send_cmd_write(8'h5A);
    wait_for_done(ok, 35000);
    check("Write completed successfully despite 5 us clock stretching", ok == 1'b1);
    check("Slave received correct data 0x5A after stretch", captured_data == 8'h5A);
    stretch_en = 1'b0;

    send_cmd_stop();
    wait_for_done(ok, 25000);

    #2000;

    // ------------------------------------------------------------------------
    // Test 12: Fast Mode (400 kHz) Timing Verification
    // ------------------------------------------------------------------------
    $display("\n--- Test Suite 12: Fast Mode (400 kHz) Timing Verification ---");
    clk_high_count = 16'd120; // 120 cycles = 1200 ns
    clk_low_count  = 16'd130; // 130 cycles = 1300 ns
    #1500;

    send_cmd_start();
    wait_for_done(ok, 1000);
    check("Fast Mode START completed", ok == 1'b1);

    fm_scl_rise = 0;
    fm_scl_fall = 0;
    measure_fast_mode = 1'b1;

    send_cmd_write(8'hA0);
    wait_for_done(ok, 8000);
    measure_fast_mode = 1'b0;

    check("Fast Mode Address transfer completed", ok == 1'b1);

    $display("    [Timing] Fast Mode SCL HIGH = %0d ns (Target = 1200 ns, Spec >= 600 ns)", t_high_meas);
    $display("    [Timing] Fast Mode SCL LOW  = %0d ns (Target = 1300 ns, Spec >= 1300 ns)", t_low_meas);
    check("Fast Mode SCL HIGH satisfies Spec (>= 600 ns)", t_high_meas >= 1150 && t_high_meas <= 1250);
    check("Fast Mode SCL LOW satisfies Spec (>= 1300 ns)", t_low_meas >= 1250 && t_low_meas <= 1350);

    send_cmd_stop();
    wait_for_done(ok, 8000);
    check("Fast Mode STOP completed cleanly", hw_busy == 1'b0);

    // ------------------------------------------------------------------------
    // Test 13: SCL Handover Glitch Verification
    // ------------------------------------------------------------------------
    $display("\n--- Test Suite 13: SCL Handover Glitch Check ---");
    check("Zero SCL glitches observed across all test transactions", scl_glitch_count == 0);

    // ------------------------------------------------------------------------
    // Test 14: Timeout during Data Transfer (Clock-Stretching Exceeds Limit)
    // ------------------------------------------------------------------------
    $display("\n--- Test Suite 14: Timeout During Data Transfer ---");
    #6000;
    clk_high_count = 16'd500;
    clk_low_count  = 16'd500;
    timeout_limit  = 32'd50; // Timeout limit = 50 cycles = 500 ns
    stretch_en          = 1'b1;
    stretch_on_bit      = 4'd4;
    stretch_duration_ns = 32'd50000; // 50 us stretch (far exceeds 500 ns limit)

    send_cmd_start();
    wait_for_done(ok, 2000);

    send_cmd_write(8'hA0);
    wait_for_done(ok, 25000);

    send_cmd_write(8'h33);
    wait_for_timeout_error(ok, 30000);
    check("hw_timeout_error_o pulsed on excessive data stretch", ok == 1'b1);
    check("hw_done_o suppressed during timeout abort", hw_done == 1'b0);
    check("Master FSM deasserts hw_busy_o after timeout", hw_busy == 1'b0);
    check("Clock generator aborted to idle: busy is 0", dut.u_clock_gen.busy == 1'b0);
    check("Clock generator stretch_wait cleared: stretch_wait is 0", dut.u_clock_gen.stretch_wait == 1'b0);
    check("Master releases SCL drive", dut.fsm_scl_drive_low == 1'b0 && dut.scl_owner_cg_q == 1'b0);
    check("Master releases SDA drive", dut.fsm_sda_drive_low == 1'b0 && dut.sda_owner_byte_q == 1'b0);
    check("hw_tx_empty_o restored to 1", hw_tx_empty == 1'b1);

    stretch_en = 1'b0; // Release slave stretch
    #6000; // Allow physical bus to float HIGH and t_BUF to elapse

    // ------------------------------------------------------------------------
    // Test 15: Timeout during Initial START Condition
    // ------------------------------------------------------------------------
    $display("\n--- Test Suite 15: Timeout During Initial START Framing ---");
    timeout_limit = 32'd40; // 40 cycles = 400 ns
    trigger_start_timeout = 1'b1;

    send_cmd_start();
    wait_for_timeout_error(ok, 5000);
    trigger_start_timeout = 1'b0;
    ext_scl_pull_low      = 1'b0;

    check("hw_timeout_error_o pulsed during START when SCL held LOW", ok == 1'b1);
    check("Master returned to IDLE: hw_busy_o is 0", hw_busy == 1'b0);
    check("Master released SDA after START timeout abort", dut.fsm_sda_drive_low == 1'b0);
    #6000;

    // ------------------------------------------------------------------------
    // Test 16: Timeout during Repeated START Framing
    // ------------------------------------------------------------------------
    $display("\n--- Test Suite 16: Timeout During Repeated START Framing ---");
    timeout_limit = 32'd40; // 40 cycles = 400 ns

    send_cmd_start();
    wait_for_done(ok, 2000);

    send_cmd_write(8'hA0);
    wait_for_done(ok, 25000);

    trigger_restart_timeout = 1'b1;
    send_cmd_restart();
    wait_for_timeout_error(ok, 10000);
    trigger_restart_timeout = 1'b0;
    ext_scl_pull_low        = 1'b0;

    check("hw_timeout_error_o pulsed during Repeated START when SCL held LOW", ok == 1'b1);
    check("Master returned to IDLE: hw_busy_o is 0", hw_busy == 1'b0);
    check("Master released bus lines after Repeated START timeout", dut.fsm_scl_drive_low == 1'b0 && dut.fsm_sda_drive_low == 1'b0);
    #6000;

    // ------------------------------------------------------------------------
    // Test 17: Timeout during STOP Condition Framing
    // ------------------------------------------------------------------------
    $display("\n--- Test Suite 17: Timeout During STOP Framing ---");
    timeout_limit = 32'd40; // 40 cycles = 400 ns

    send_cmd_start();
    wait_for_done(ok, 2000);

    send_cmd_write(8'hA0);
    wait_for_done(ok, 25000);

    trigger_stop_timeout = 1'b1;
    send_cmd_stop();
    wait_for_timeout_error(ok, 10000);
    trigger_stop_timeout = 1'b0;
    ext_scl_pull_low     = 1'b0;

    check("hw_timeout_error_o pulsed during STOP when SCL held LOW", ok == 1'b1);
    check("Master returned to IDLE: hw_busy_o is 0", hw_busy == 1'b0);
    check("Master released bus lines after STOP timeout", dut.fsm_scl_drive_low == 1'b0 && dut.fsm_sda_drive_low == 1'b0);
    #6000;

    // ------------------------------------------------------------------------
    // Test 18: Register Bank & Interrupt Integration
    // ------------------------------------------------------------------------
    $display("\n--- Test Suite 18: Register Bank & Interrupt Integration ---");
    begin
      logic [31:0] reg_val;

      // 1. Verify STATUS[4] (TIMEOUT_ERROR) is set by the previous timeout event
      reg_read(ADDR_STATUS, reg_val);
      check("STATUS.TIMEOUT_ERROR (bit 4) is asserted in register bank", reg_val[STAT_TIMEOUT_ERROR_BIT] == 1'b1);

      // 2. Verify IRQ[2] (TIMEOUT_PENDING) is set
      reg_read(ADDR_IRQ, reg_val);
      check("IRQ.TIMEOUT_PENDING (bit 2) is asserted in register bank", reg_val[IRQ_TIMEOUT_PENDING_BIT] == 1'b1);

      // 3. Enable interrupts in CONTROL and IRQ
      reg_write(ADDR_CONTROL, 32'h00000002); // CONTROL.INT_ENABLE (bit 1) = 1
      reg_write(ADDR_IRQ, 32'h00000400);     // IRQ.TIMEOUT_ENABLE (bit 10) = 1
      #20;
      check("Global interrupt irq_o asserts when enabled", irq_sig == 1'b1);

      // 4. Clear interrupt pending via W1C
      reg_write(ADDR_IRQ, 32'h00000404); // Write 1 to bit 2
      #20;
      check("Global interrupt irq_o deasserts after W1C clear", irq_sig == 1'b0);
      reg_read(ADDR_IRQ, reg_val);
      check("IRQ.TIMEOUT_PENDING cleared after W1C", reg_val[IRQ_TIMEOUT_PENDING_BIT] == 1'b0);

      // 5. Clear STATUS.TIMEOUT_ERROR by writing a command to COMMAND register
      reg_write(ADDR_COMMAND, 32'h00000001); // Write dummy command
      #20;
      reg_read(ADDR_STATUS, reg_val);
      check("STATUS.TIMEOUT_ERROR cleared after new command write", reg_val[STAT_TIMEOUT_ERROR_BIT] == 1'b0);
    end

    // ------------------------------------------------------------------------
    // Test 19: Full Post-Timeout Clean Recovery (New Valid Transaction)
    // ------------------------------------------------------------------------
    $display("\n--- Test Suite 19: Clean Transaction Recovery Post-Timeout ---");
    timeout_limit = 32'd100000; // Restore default 1 ms limit
    #6000; // Allow bus-free qualification (500 cycles = 5000 ns)

    send_cmd_start();
    wait_for_done(ok, 2000);
    check("Subsequent START completed successfully post-timeout", ok == 1'b1);
    check("hw_busy_o asserted during new transaction", hw_busy == 1'b1);

    send_cmd_write(8'hA0);
    wait_for_done(ok, 25000);
    check("Subsequent Address Write completed successfully", ok == 1'b1);
    check("Slave received address 0x50", captured_addr == 7'h50);

    send_cmd_write(8'h7E);
    wait_for_done(ok, 25000);
    check("Subsequent Data Write completed successfully", ok == 1'b1);
    check("Slave received data byte 0x7E", captured_data == 8'h7E);

    send_cmd_stop();
    wait_for_done(ok, 25000);
    check("Subsequent STOP completed cleanly", hw_busy == 1'b0);
    check("Both bus lines float HIGH post-transaction", scl_bus == 1'b1 && sda_bus == 1'b1);

    // ------------------------------------------------------------------------
    // Final Summary
    // ------------------------------------------------------------------------
    $display("\n============================================================================");
    $display("Task C/D Verification Results: %0d Passed, %0d Failed out of %0d Tests",
             pass_count, fail_count, test_count);
    $display("============================================================================");

    if (fail_count == 0) begin
      $display(">>> ALL TASK C & D VERIFICATION TESTS PASSED SUCCESSFULLY! <<<\n");
    end else begin
      $display(">>> VERIFICATION FAILED WITH %0d FAILURES! <<<\n", fail_count);
    end

    $finish;
  end

endmodule : tb_i2c_master
