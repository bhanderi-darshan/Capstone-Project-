// ============================================================================
// File:        tb_i2c_clock_gen.sv
// Project:     AHB-Lite to I2C Master Controller
// Description: Comprehensive self-checking testbench for Task B (i2c_clock_gen).
//              Verifies:
//              1. Reset behavior (bus released, all flags idle)
//              2. Normal SCL cycle execution
//              3. 100 kHz Standard Mode (HIGH_COUNT=500, LOW_COUNT=500, 10 us period)
//              4. 400 kHz Fast Mode (HIGH_COUNT=120, LOW_COUNT=130, 2.5 us period)
//              5. Asymmetric counts (e.g. LOW=40, HIGH=60)
//              6. Exactly 1-cycle cycle_done pulse width
//              7. No repeated/spurious cycle_done pulses in IDLE
//              8. Short clock stretching (10 HCLK cycles)
//              9. Long clock stretching (200 HCLK cycles)
//              10. Transition and timing accuracy post-stretch
//              11. Invariant: No HIGH phase counting before physical SCL rises
//              12. Lockout protection (start_cycle ignored when busy)
//              13. Boundary conditions (HIGH_COUNT=1, LOW_COUNT=1)
//              14. Zero-count clamping (0 clamped to 1 cycle)
// Standard:    SystemVerilog IEEE 1800-2012
// ============================================================================

`timescale 1ns / 1ps

module tb_i2c_clock_gen;

  // --------------------------------------------------------------------------
  // Clock & Reset Signals
  // --------------------------------------------------------------------------
  logic        clk;
  logic        reset_n;

  // --------------------------------------------------------------------------
  // DUT Interface Signals
  // --------------------------------------------------------------------------
  logic        start_cycle;
  logic [15:0] high_count;
  logic [15:0] low_count;
  logic        scl_in;
  logic        abort_sig;

  logic        scl_drive_low;
  logic        busy;
  logic        cycle_done;
  logic        stretch_wait;

  // --------------------------------------------------------------------------
  // Emulated Physical Bus & Slave Signals
  // --------------------------------------------------------------------------
  logic        slave_pull_down; // Emulates an I2C slave holding SCL LOW (clock stretching)

  // Wired-AND open-drain bus with pull-up resistor:
  // Driven LOW if either master or slave pulls it down; otherwise floats HIGH (1'b1)
  wire scl_physical = (scl_drive_low || slave_pull_down) ? 1'b0 : 1'b1;

  // Connect physical line to DUT input
  assign scl_in = scl_physical;

  // --------------------------------------------------------------------------
  // Test Tracking
  // --------------------------------------------------------------------------
  int test_count = 0;
  int pass_count = 0;
  int fail_count = 0;

  // --------------------------------------------------------------------------
  // DUT Instantiation
  // --------------------------------------------------------------------------
  i2c_clock_gen u_clock_gen (
      .clk          (clk),
      .reset_n      (reset_n),
      .start_cycle  (start_cycle),
      .high_count   (high_count),
      .low_count    (low_count),
      .scl_in       (scl_in),
      .abort        (abort_sig),
      .scl_drive_low(scl_drive_low),
      .busy         (busy),
      .cycle_done   (cycle_done),
      .stretch_wait (stretch_wait)
  );

  // --------------------------------------------------------------------------
  // 100 MHz Clock Generator (Period = 10.0 ns, Half-period = 5.0 ns)
  // --------------------------------------------------------------------------
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  // Watchdog Timer (2 ms simulation time limit)
  initial begin
    #2000000;
    $display("\n[FATAL] Watchdog timeout triggered at %0t! Simulation aborted.", $time);
    $finish;
  end

  // --------------------------------------------------------------------------
  // Check Assertion Helper
  // --------------------------------------------------------------------------
  task automatic check(input string test_name, input logic cond, input string detail);
    begin
      test_count++;
      if (cond) begin
        $display("[PASS] %s: %s", test_name, detail);
        pass_count++;
      end else begin
        $display("[FAIL] %s: %s", test_name, detail);
        fail_count++;
      end
    end
  endtask

  // --------------------------------------------------------------------------
  // Cycle Measurement Task (Negedge Sampled, Race-Free)
  // --------------------------------------------------------------------------
  task automatic run_and_measure_cycle(
      input  [15:0] low_cnt,
      input  [15:0] high_cnt,
      output int    measured_low_cycles,
      output int    measured_high_cycles,
      output int    done_pulse_width
  );
    begin
      low_count   <= low_cnt;
      high_count  <= high_cnt;
      measured_low_cycles  = 0;
      measured_high_cycles = 0;
      done_pulse_width     = 0;

      // Ensure we are in IDLE
      while (busy) @(posedge clk);

      // Pulse start_cycle for 1 cycle
      @(posedge clk);
      start_cycle <= 1'b1;
      @(posedge clk);
      start_cycle <= 1'b0;

      // Count SCL LOW cycles (sampled at negedge for race-free measurement)
      @(negedge clk);
      while (scl_drive_low == 1'b1) begin
        measured_low_cycles++;
        @(negedge clk);
      end

      // Wait if slave is clock stretching
      while (scl_physical == 1'b0) begin
        @(negedge clk);
      end

      // Count SCL HIGH cycles (sampled at negedge while SCL is released)
      while (scl_drive_low == 1'b0) begin
        measured_high_cycles++;
        @(negedge clk);
      end

      // Measure cycle_done pulse width in clock cycles
      while (cycle_done) begin
        done_pulse_width++;
        @(negedge clk);
      end

      // Wait until DUT returns to IDLE
      while (busy) @(posedge clk);
      @(posedge clk);
    end
  endtask

  // --------------------------------------------------------------------------
  // Main Verification Process
  // --------------------------------------------------------------------------
  int low_dur, high_dur, done_width;

  initial begin
    $dumpfile("sim/tb_i2c_clock_gen.vcd");
    $dumpvars(0, tb_i2c_clock_gen);

    $display("==================================================================");
    $display("      STARTING TASK B VERIFICATION: I2C CLOCK GENERATOR           ");
    $display("==================================================================");

    // Initial state
    reset_n         = 1'b0;
    start_cycle     = 1'b0;
    high_count      = 16'd500;
    low_count       = 16'd500;
    slave_pull_down = 1'b0;
    abort_sig       = 1'b0;

    // Apply Reset
    #30;
    @(posedge clk);
    reset_n = 1'b1;
    $display("[INFO] System reset deasserted.");
    @(posedge clk);

    // ------------------------------------------------------------------------
    // TC01: Reset Behavior
    // ------------------------------------------------------------------------
    $display("\n--- TC01: Reset Behavior ---");
    check("TC01_scl_released", (scl_drive_low == 1'b0), "scl_drive_low is 0 (SCL released at reset)");
    check("TC01_busy_idle",    (busy == 1'b0),          "busy is 0 in IDLE");
    check("TC01_done_idle",    (cycle_done == 1'b0),    "cycle_done is 0 in IDLE");
    check("TC01_stretch_idle", (stretch_wait == 1'b0),  "stretch_wait is 0 in IDLE");

    // ------------------------------------------------------------------------
    // TC02: Normal SCL Cycle Execution
    // ------------------------------------------------------------------------
    $display("\n--- TC02: Normal SCL Cycle Execution ---");
    run_and_measure_cycle(16'd20, 16'd20, low_dur, high_dur, done_width);
    check("TC02_cycle_ran", (low_dur == 20 && high_dur == 20),
          $sformatf("Executed cycle: low=%0d, high=%0d cycles", low_dur, high_dur));
    check("TC02_hold_low",  (scl_drive_low == 1'b1),
          "After cycle completion: SCL held LOW in IDLE as required");

    // ------------------------------------------------------------------------
    // TC03: 100 kHz Standard Mode (500 Low, 500 High = 10,000 ns period)
    // ------------------------------------------------------------------------
    $display("\n--- TC03: 100 kHz Standard Mode Timing Verification ---");
    run_and_measure_cycle(16'd500, 16'd500, low_dur, high_dur, done_width);
    check("TC03_low_duration",  (low_dur == 500),  $sformatf("Low duration = %0d cycles (expected 500 = 5000 ns)", low_dur));
    check("TC03_high_duration", (high_dur == 500), $sformatf("High duration = %0d cycles (expected 500 = 5000 ns)", high_dur));
    check("TC03_total_period",  (low_dur + high_dur == 1000),
          $sformatf("Total period = %0d cycles (10,000 ns = 100.00 kHz)", low_dur + high_dur));

    // ------------------------------------------------------------------------
    // TC04: 400 kHz Fast Mode (130 Low, 120 High = 2,500 ns period)
    // ------------------------------------------------------------------------
    $display("\n--- TC04: 400 kHz Fast Mode Timing Verification ---");
    run_and_measure_cycle(16'd130, 16'd120, low_dur, high_dur, done_width);
    check("TC04_low_duration",  (low_dur == 130),  $sformatf("Low duration = %0d cycles (expected 130 = 1300 ns)", low_dur));
    check("TC04_high_duration", (high_dur == 120), $sformatf("High duration = %0d cycles (expected 120 = 1200 ns)", high_dur));
    check("TC04_total_period",  (low_dur + high_dur == 250),
          $sformatf("Total period = %0d cycles (2,500 ns = 400.00 kHz)", low_dur + high_dur));

    // ------------------------------------------------------------------------
    // TC05: Asymmetric Timing Configurations
    // ------------------------------------------------------------------------
    $display("\n--- TC05: Asymmetric Timing Verification ---");
    run_and_measure_cycle(16'd40, 16'd60, low_dur, high_dur, done_width);
    check("TC05_asymm_low",  (low_dur == 40),  $sformatf("Low duration = %0d cycles (expected 40)", low_dur));
    check("TC05_asymm_high", (high_dur == 60), $sformatf("High duration = %0d cycles (expected 60)", high_dur));

    // ------------------------------------------------------------------------
    // TC06: Exact 1-Cycle cycle_done Pulse Width
    // ------------------------------------------------------------------------
    $display("\n--- TC06: cycle_done Pulse Width Verification ---");
    check("TC06_pulse_width", (done_width == 1),
          $sformatf("cycle_done pulse width = %0d cycle (expected exactly 1)", done_width));

    // ------------------------------------------------------------------------
    // TC07: No Spurious cycle_done Pulses in IDLE
    // ------------------------------------------------------------------------
    $display("\n--- TC07: No Spurious cycle_done in IDLE ---");
    repeat (20) begin
      @(posedge clk);
      if (cycle_done) fail_count++;
    end
    check("TC07_idle_clean", (cycle_done == 1'b0), "cycle_done remained 0 throughout IDLE");

    // ------------------------------------------------------------------------
    // TC08: Short Clock Stretching (10 HCLK Cycles)
    // ------------------------------------------------------------------------
    $display("\n--- TC08: Short Clock Stretching (10 Cycles) ---");
    low_count   <= 16'd30;
    high_count  <= 16'd30;
    @(posedge clk);
    start_cycle <= 1'b1;
    @(posedge clk);
    start_cycle <= 1'b0;

    // While SCL is LOW, slave pulls SCL down in preparation for stretching
    repeat (15) @(posedge clk);
    slave_pull_down <= 1'b1; // Slave holds SCL line

    // Wait until master finishes LOW phase and releases SCL
    while (scl_drive_low == 1'b1) @(posedge clk);

    // Master has released SCL, but slave is stretching it for 10 cycles
    repeat (10) begin
      @(posedge clk);
      check("TC08_stretch_flag", (stretch_wait == 1'b1), "stretch_wait is 1 while slave pulls SCL down");
    end

    // Slave releases SCL
    slave_pull_down <= 1'b0;
    @(posedge clk);

    // Verify stretch_wait clears and cycle completes cleanly
    while (busy) @(posedge clk);
    check("TC08_stretch_complete", (stretch_wait == 1'b0 && busy == 1'b0),
          "Clock stretch released cleanly, cycle completed");

    // ------------------------------------------------------------------------
    // TC09: Long Clock Stretching (200 HCLK Cycles)
    // ------------------------------------------------------------------------
    $display("\n--- TC09: Long Clock Stretching (200 Cycles) ---");
    low_count   <= 16'd20;
    high_count  <= 16'd20;
    @(posedge clk);
    start_cycle <= 1'b1;
    @(posedge clk);
    start_cycle <= 1'b0;

    // Slave asserts stretch during LOW phase
    repeat (10) @(posedge clk);
    slave_pull_down <= 1'b1;

    // Wait until master releases SCL
    while (scl_drive_low == 1'b1) @(posedge clk);

    // Hold stretch for 200 cycles
    repeat (200) @(posedge clk);
    check("TC09_long_stretch", (stretch_wait == 1'b1), "stretch_wait held active over 200 cycles");

    // Release stretch
    slave_pull_down <= 1'b0;
    while (busy) @(posedge clk);
    check("TC09_recovered", (busy == 1'b0), "Recovered from 200-cycle stretch cleanly");

    // ------------------------------------------------------------------------
    // TC10: Recovery after Clock Stretch & High Phase Timing Verification
    // ------------------------------------------------------------------------
    $display("\n--- TC10: HIGH Phase Accuracy Post-Stretch ---");
    low_count  <= 16'd25;
    high_count <= 16'd40;
    @(posedge clk);
    start_cycle <= 1'b1;
    @(posedge clk);
    start_cycle <= 1'b0;

    // Pull stretch during LOW phase
    repeat (15) @(posedge clk);
    slave_pull_down <= 1'b1;

    // Wait until master releases SCL
    while (scl_drive_low == 1'b1) @(posedge clk);

    // Stretch for 50 cycles
    repeat (50) @(posedge clk);
    slave_pull_down <= 1'b0;

    // Count HIGH duration from when physical SCL rises to when SCL is pulled LOW again
    while (scl_physical == 1'b0) @(posedge clk);
    high_dur = 0;
    while (scl_drive_low == 1'b0 && busy) begin
      high_dur++;
      @(posedge clk);
    end
    check("TC10_post_stretch_high", (high_dur == 40),
          $sformatf("Post-stretch HIGH duration = %0d cycles (expected exactly 40)", high_dur));

    while (busy) @(posedge clk);

    // ------------------------------------------------------------------------
    // TC11: No High Phase Counting Before SCL Rises
    // ------------------------------------------------------------------------
    $display("\n--- TC11: High Counter Invariant Verification ---");
    low_count  <= 16'd20;
    high_count <= 16'd50;
    @(posedge clk);
    start_cycle <= 1'b1;
    @(posedge clk);
    start_cycle <= 1'b0;

    repeat (10) @(posedge clk);
    slave_pull_down <= 1'b1;

    while (scl_drive_low == 1'b1) @(posedge clk);

    // Hold SCL low for 80 cycles (longer than high_count = 50)
    repeat (80) @(posedge clk);
    check("TC11_no_premature_done", (cycle_done == 1'b0 && busy == 1'b1),
          "High phase did NOT advance while SCL was held LOW");
    slave_pull_down <= 1'b0;
    while (busy) @(posedge clk);

    // ------------------------------------------------------------------------
    // TC12: Lockout Protection (start_cycle ignored when busy)
    // ------------------------------------------------------------------------
    $display("\n--- TC12: Lockout Protection (Busy Ignore) ---");
    low_count  <= 16'd50;
    high_count <= 16'd50;
    @(posedge clk);
    start_cycle <= 1'b1;
    @(posedge clk);
    start_cycle <= 1'b0;

    // Attempt spurious start_cycle during active operation
    repeat (10) @(posedge clk);
    start_cycle <= 1'b1; // SPURIOUS PULSE!
    @(posedge clk);
    start_cycle <= 1'b0;

    // Verify it completes cleanly without double-cycle or corruption
    done_width = 0;
    while (busy) begin
      if (cycle_done) done_width++;
      @(posedge clk);
    end
    check("TC12_lockout_success", (done_width == 1),
          "Spurious start_cycle while busy was correctly ignored; exactly 1 cycle_done observed");

    // ------------------------------------------------------------------------
    // TC13: Boundary Condition (Minimum Counts = 1)
    // ------------------------------------------------------------------------
    $display("\n--- TC13: Boundary Counts (LOW=1, HIGH=1) ---");
    run_and_measure_cycle(16'd1, 16'd1, low_dur, high_dur, done_width);
    check("TC13_min_low",  (low_dur == 1),  $sformatf("Minimum LOW duration = %0d cycle (expected 1)", low_dur));
    check("TC13_min_high", (high_dur == 1), $sformatf("Minimum HIGH duration = %0d cycle (expected 1)", high_dur));

    // ------------------------------------------------------------------------
    // TC14: Zero-Count Clamping Handling (0 Clamped to 1 Cycle)
    // ------------------------------------------------------------------------
    $display("\n--- TC14: Zero-Count Hardware Clamping ---");
    // Case 1: Both zero
    run_and_measure_cycle(16'd0, 16'd0, low_dur, high_dur, done_width);
    check("TC14_both_zero_low",  (low_dur == 1),  $sformatf("LOW=0 clamped to %0d cycle (expected 1)", low_dur));
    check("TC14_both_zero_high", (high_dur == 1), $sformatf("HIGH=0 clamped to %0d cycle (expected 1)", high_dur));

    // Case 2: LOW=0, HIGH=20
    run_and_measure_cycle(16'd0, 16'd20, low_dur, high_dur, done_width);
    check("TC14_low_zero_clamped", (low_dur == 1 && high_dur == 20),
          $sformatf("LOW=0 clamped to 1, HIGH=20: low=%0d, high=%0d", low_dur, high_dur));

    // Case 3: LOW=20, HIGH=0
    run_and_measure_cycle(16'd20, 16'd0, low_dur, high_dur, done_width);
    check("TC14_high_zero_clamped", (low_dur == 20 && high_dur == 1),
          $sformatf("LOW=20, HIGH=0 clamped to 1: low=%0d, high=%0d", low_dur, high_dur));

    // ------------------------------------------------------------------------
    // TC15: Synchronous Abort During Active SCL_LOW Phase
    // ------------------------------------------------------------------------
    $display("\n--- TC15: Synchronous Abort During Active Cycle ---");
    low_count  <= 16'd50;
    high_count <= 16'd50;
    @(posedge clk);
    start_cycle <= 1'b1;
    @(posedge clk);
    start_cycle <= 1'b0;

    repeat (10) @(posedge clk);
    check("TC15_busy_before_abort", (busy == 1'b1), "busy is 1 during active SCL_LOW");

    // Assert synchronous abort pulse
    abort_sig <= 1'b1;
    @(posedge clk);
    abort_sig <= 1'b0;
    #1; // Sample immediately after NBA update

    check("TC15_busy_cleared", (busy == 1'b0), "busy cleared to 0 immediately on abort");
    check("TC15_stretch_cleared", (stretch_wait == 1'b0), "stretch_wait is 0 on abort");
    check("TC15_done_suppressed", (cycle_done == 1'b0), "cycle_done suppressed to 0 on abort");
    check("TC15_scl_released", (scl_drive_low == 1'b0), "scl_drive_low deasserted to 0 on abort");
    check("TC15_state_idle", (u_clock_gen.state_q == u_clock_gen.STATE_IDLE), "clock generator restored to STATE_IDLE");

    // ------------------------------------------------------------------------
    // TC16: Synchronous Abort Concurrent with cycle_done
    // ------------------------------------------------------------------------
    $display("\n--- TC16: Synchronous Abort Concurrent with cycle_done ---");
    low_count  <= 16'd5;
    high_count <= 16'd5;
    @(posedge clk);
    start_cycle <= 1'b1;
    @(posedge clk);
    start_cycle <= 1'b0;

    // Wait until in STATE_SCL_HIGH counting near end of high phase
    while (u_clock_gen.state_q != u_clock_gen.STATE_SCL_HIGH || u_clock_gen.count_q < 5) @(posedge clk);

    // Assert abort on the final cycle of HIGH phase where cycle_done would be scheduled
    abort_sig <= 1'b1;
    @(posedge clk);
    abort_sig <= 1'b0;
    #1;

    check("TC16_done_suppressed", (cycle_done == 1'b0), "cycle_done strictly suppressed by concurrent abort");
    check("TC16_busy_cleared", (busy == 1'b0), "busy cleared to 0 by concurrent abort");
    check("TC16_state_idle", (u_clock_gen.state_q == u_clock_gen.STATE_IDLE), "returned to STATE_IDLE");

    // ------------------------------------------------------------------------
    // TC17: Clean Cycle Execution Post-Abort
    // ------------------------------------------------------------------------
    $display("\n--- TC17: Clean Cycle Execution Post-Abort ---");
    run_and_measure_cycle(16'd10, 16'd10, low_dur, high_dur, done_width);
    check("TC17_post_abort_cycle", (low_dur == 10 && high_dur == 10 && done_width == 1),
          $sformatf("Post-abort cycle executed cleanly: low=%0d, high=%0d, done_width=%0d", low_dur, high_dur, done_width));
    check("TC17_post_abort_busy", (busy == 1'b0), "busy is 0 after post-abort cycle completes");

    // ------------------------------------------------------------------------
    // Final Summary
    // ------------------------------------------------------------------------
    $display("\n==================================================================");
    $display("                      TASK B TEST SUMMARY                         ");
    $display("==================================================================");
    $display("  TOTAL TESTS : %0d", test_count);
    $display("  PASSED      : %0d", pass_count);
    $display("  FAILED      : %0d", fail_count);
    $display("==================================================================");

    if (fail_count == 0) begin
      $display("  >>> ALL TASK B TESTS PASSED SUCCESSFULLY! <<<");
    end else begin
      $display("  >>> SOME TESTS FAILED. PLEASE INVESTIGATE! <<<");
    end
    $display("==================================================================\n");

    $finish;
  end

endmodule : tb_i2c_clock_gen
