// ============================================================================
// File:        tb_i2c_timeout.sv
// Project:     AHB-Lite to I2C Master Controller
// Description: Unit testbench for i2c_timeout module (Task D).
//              Verifies:
//              1. Asynchronous reset behavior
//              2. TIMEOUT_LIMIT = 0 disables timeout
//              3. SCL rising before threshold clears counter
//              4. Exact-N cycle threshold assertion (deterministic N = 5)
//              5. Single pulse guarantee across continuous stretch episode
//              6. Re-triggering capability across distinct stretch episodes
//              7. Counter clearing on master SCL pull-down (scl_released = 0)
//              8. Asynchronous reset during active stretch episode
// Standard:    SystemVerilog IEEE 1800-2012
// ============================================================================

`timescale 1ns / 1ps

module tb_i2c_timeout;

  // --------------------------------------------------------------------------
  // Clock and Reset Signals (100 MHz HCLK)
  // --------------------------------------------------------------------------
  logic        clk;
  logic        reset_n;

  // DUT Signals
  logic        scl_released;
  logic        scl_in;
  logic [31:0] timeout_limit;
  logic        timeout_event;
  logic        stretch_active;

  // --------------------------------------------------------------------------
  // Clock Generation (100 MHz, Period = 10 ns)
  // --------------------------------------------------------------------------
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // --------------------------------------------------------------------------
  // DUT Instantiation
  // --------------------------------------------------------------------------
  i2c_timeout dut (
      .clk           (clk),
      .reset_n       (reset_n),
      .scl_released  (scl_released),
      .scl_in        (scl_in),
      .timeout_limit (timeout_limit),
      .timeout_event (timeout_event),
      .stretch_active(stretch_active)
  );

  // --------------------------------------------------------------------------
  // Test Tracking Utilities
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

  // --------------------------------------------------------------------------
  // Test Execution Sequence
  // --------------------------------------------------------------------------
  initial begin
    $dumpfile("sim/tb_i2c_timeout.vcd");
    $dumpvars(0, tb_i2c_timeout);

    $display("==================================================================");
    $display("Starting Unit Verification: i2c_timeout (Task D)");
    $display("==================================================================");

    // Initial state
    reset_n       = 1'b0;
    scl_released  = 1'b0;
    scl_in        = 1'b1;
    timeout_limit = 32'd0;
    #25;
    @(posedge clk);

    // ------------------------------------------------------------------------
    // Test 1: Reset State Behavior
    // ------------------------------------------------------------------------
    $display("\n--- Test Suite 1: Reset State Behavior ---");
    check("timeout_event is 0 at reset", timeout_event == 1'b0);
    check("stretch_active is 0 at reset", stretch_active == 1'b0);
    check("Internal count_q is 0 at reset", dut.count_q == 32'd0);

    // Release reset
    reset_n = 1'b1;
    #20;
    @(posedge clk);
    check("timeout_event remains 0 post-reset", timeout_event == 1'b0);

    // ------------------------------------------------------------------------
    // Test 2: Timeout Disabled When TIMEOUT_LIMIT = 0
    // ------------------------------------------------------------------------
    $display("\n--- Test Suite 2: Timeout Disabled (TIMEOUT_LIMIT = 0) ---");
    timeout_limit = 32'd0;
    scl_released  = 1'b1;
    scl_in        = 1'b0; // Clock stretch condition active
    #1;
    check("stretch_active asserts when scl_released=1 and scl_in=0", stretch_active == 1'b1);

    repeat (20) @(posedge clk);
    check("timeout_event NEVER fires when limit is 0", timeout_event == 1'b0);
    check("count_q remains 0 when limit is 0", dut.count_q == 32'd0);

    // Release SCL between tests
    scl_in = 1'b1;
    @(posedge clk);

    // ------------------------------------------------------------------------
    // Test 3: SCL Rises Before Timeout Limit
    // ------------------------------------------------------------------------
    $display("\n--- Test Suite 3: SCL Rises Before Timeout Limit ---");
    timeout_limit = 32'd10;
    scl_released  = 1'b1;
    scl_in        = 1'b0;

    repeat (4) @(posedge clk);
    #1;
    check("Count reaches 4 cycles without firing event", dut.count_q == 32'd4 && timeout_event == 1'b0);

    // SCL rises HIGH (slave releases stretch)
    scl_in = 1'b1;
    @(posedge clk);
    #1;
    check("stretch_active deasserts on SCL rise", stretch_active == 1'b0);
    check("count_q clears to 0 on SCL rise", dut.count_q == 32'd0);
    check("No timeout event generated", timeout_event == 1'b0);

    // ------------------------------------------------------------------------
    // Test 4: Master Reclaims SCL (Pulls SCL LOW) Clears Counter
    // ------------------------------------------------------------------------
    $display("\n--- Test Suite 4: Master Pulls SCL LOW Clears Counter ---");
    scl_in        = 1'b0;
    scl_released  = 1'b1;
    repeat (3) @(posedge clk);
    #1;
    check("Count reached 3 cycles during stretch", dut.count_q == 32'd3);

    // Master pulls SCL LOW (scl_released = 0)
    scl_released = 1'b0;
    @(posedge clk);
    #1;
    check("count_q clears to 0 when master pulls SCL LOW", dut.count_q == 32'd0);
    check("stretch_active deasserts when master pulls SCL LOW", stretch_active == 1'b0);

    // ------------------------------------------------------------------------
    // Test 5: Exact-N Cycle Threshold Assertion (Deterministic N = 5)
    // ------------------------------------------------------------------------
    $display("\n--- Test Suite 5: Exact-N Cycle Assertion (N = 5) ---");
    timeout_limit = 32'd5;
    scl_in        = 1'b0;
    scl_released  = 1'b1;

    // Cycle 1
    @(posedge clk); #1;
    check("Cycle 1: count=1, timeout_event=0", dut.count_q == 32'd1 && timeout_event == 1'b0);

    // Cycle 2
    @(posedge clk); #1;
    check("Cycle 2: count=2, timeout_event=0", dut.count_q == 32'd2 && timeout_event == 1'b0);

    // Cycle 3
    @(posedge clk); #1;
    check("Cycle 3: count=3, timeout_event=0", dut.count_q == 32'd3 && timeout_event == 1'b0);

    // Cycle 4
    @(posedge clk); #1;
    check("Cycle 4: count=4, timeout_event=0", dut.count_q == 32'd4 && timeout_event == 1'b0);

    // Cycle 5: EXACT N-th CYCLE!
    @(posedge clk); #1;
    check("Cycle 5: count=5, timeout_event=1 (EXACT-N ASSERTION!)", dut.count_q == 32'd5 && timeout_event == 1'b1);

    // Cycle 6: Must deassert event (1-cycle pulse guarantee)
    @(posedge clk); #1;
    check("Cycle 6: timeout_event drops to 0 (single pulse guarantee)", timeout_event == 1'b0);
    check("Cycle 6: timeout_fired_q latched active", dut.timeout_fired_q == 1'b1);

    // Cycle 7 to 15: Continued stretch must not generate additional events
    repeat (10) @(posedge clk);
    #1;
    check("Continued stretch generates zero additional timeout events", timeout_event == 1'b0);

    // ------------------------------------------------------------------------
    // Test 6: Episode Termination and Re-Triggering on Second Episode
    // ------------------------------------------------------------------------
    $display("\n--- Test Suite 6: Recovery and Second Episode Re-Triggering ---");
    // End first episode by releasing slave stretch
    scl_in = 1'b1;
    @(posedge clk);
    #1;
    check("Episode end: count_q reset to 0", dut.count_q == 32'd0);
    check("Episode end: timeout_fired_q cleared", dut.timeout_fired_q == 1'b0);

    // Begin second distinct stretch episode
    scl_in = 1'b0;
    repeat (4) @(posedge clk);
    @(posedge clk); #1;
    check("Second episode fires new timeout event on 5th cycle", timeout_event == 1'b1);

    @(posedge clk); #1;
    check("Second episode event deasserts after 1 cycle", timeout_event == 1'b0);

    // ------------------------------------------------------------------------
    // Test 7: Asynchronous Reset During Active Stretch
    // ------------------------------------------------------------------------
    $display("\n--- Test Suite 7: Asynchronous Reset During Active Stretch ---");
    scl_in = 1'b1;
    @(posedge clk);
    scl_in = 1'b0;
    repeat (3) @(posedge clk);
    #2;
    reset_n = 1'b0; // Asynchronous reset assertion
    #1;
    check("Async reset immediately clears count_q to 0", dut.count_q == 32'd0);
    check("Async reset immediately forces timeout_event to 0", timeout_event == 1'b0);
    check("Async reset immediately forces timeout_fired_q to 0", dut.timeout_fired_q == 1'b0);

    reset_n = 1'b1;
    #20;

    // ------------------------------------------------------------------------
    // Test 8: SCL Rising HIGH Concurrent with Timeout Threshold Edge
    // ------------------------------------------------------------------------
    $display("\n--- Test Suite 8: SCL Rising Concurrent with Threshold Edge ---");
    scl_released  = 1'b1;
    timeout_limit = 32'd5;
    scl_in        = 1'b1;
    @(posedge clk);

    // Case A: SCL rises HIGH exactly on the 5th sample edge
    scl_in = 1'b0; // Begin stretch
    repeat (4) @(posedge clk); // Cycles 1, 2, 3, 4
    #1;
    check("Cycles 1-4 elapsed: count_q is 4", dut.count_q == 32'd4);
    scl_in = 1'b1; // SCL rises HIGH on the 5th sample edge
    @(posedge clk); #1;
    check("SCL rose on 5th edge: timeout_event suppressed (0)", timeout_event == 1'b0);
    check("SCL rose on 5th edge: count_q reset to 0", dut.count_q == 32'd0);
    check("SCL rose on 5th edge: stretch_active is 0", stretch_active == 1'b0);

    // Case B: SCL remains LOW through cycle 5 (timeout fires), then rises on cycle 6
    scl_in = 1'b0; // Begin stretch
    repeat (4) @(posedge clk); // Cycles 1, 2, 3, 4
    @(posedge clk); #1; // Cycle 5: Threshold reached!
    check("Cycle 5: timeout_event pulsed HIGH on exact threshold", timeout_event == 1'b1);
    scl_in = 1'b1; // SCL rises immediately on cycle 6
    @(posedge clk); #1; // Cycle 6: SCL is now HIGH
    check("Cycle 6: timeout_event deasserted back to 0", timeout_event == 1'b0);
    check("Cycle 6: count_q cleared to 0 upon SCL rising HIGH", dut.count_q == 32'd0);
    check("Cycle 6: timeout_fired_q cleared upon SCL rising HIGH", dut.timeout_fired_q == 1'b0);

    // ------------------------------------------------------------------------
    // Final Summary
    // ------------------------------------------------------------------------
    $display("\n==================================================================");
    $display("i2c_timeout Unit Verification Results: %0d Passed, %0d Failed",
             pass_count, fail_count);
    $display("==================================================================");

    if (fail_count == 0) begin
      $display(">>> ALL i2c_timeout UNIT TESTS PASSED SUCCESSFULLY! <<<\n");
    end else begin
      $display(">>> i2c_timeout UNIT TESTS FAILED WITH %0d FAILURES! <<<\n", fail_count);
    end

    $finish;
  end

endmodule : tb_i2c_timeout

