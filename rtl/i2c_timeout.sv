// ============================================================================
// File:        i2c_timeout.sv
// Project:     AHB-Lite to I2C Master Controller
// Description: Programmable Hardware Clock-Stretching Timeout Counter.
//              Monitors physical SCL line when released by master.
//              Asserts 1-cycle timeout event if physical SCL remains LOW
//              for exactly N consecutive qualifying HCLK cycles.
// Standard:    SystemVerilog IEEE 1800-2012 (Synthesizable)
// ============================================================================

`timescale 1ns / 1ps

module i2c_timeout (
    input  logic        clk,            // 100 MHz System Clock (HCLK)
    input  logic        reset_n,        // Active-low asynchronous reset
    input  logic        scl_released,   // 1 = Master has released SCL (open-drain floating HIGH)
    input  logic        scl_in,         // Synchronized physical SCL bus input
    input  logic [31:0] timeout_limit,  // Programmable limit in HCLK cycles (0 = disabled)
    output logic        timeout_event,  // 1-cycle active-HIGH timeout pulse
    output logic        stretch_active  // 1 = Clock stretching currently observed
);

  // --------------------------------------------------------------------------
  // Clock Stretching Qualification
  // --------------------------------------------------------------------------
  // Clock stretching is active when master has released SCL, but physical SCL remains LOW
  assign stretch_active = scl_released && !scl_in;

  // --------------------------------------------------------------------------
  // Internal Counter and Fired State Flag
  // --------------------------------------------------------------------------
  logic [31:0] count_q;
  logic        timeout_fired_q;

  // --------------------------------------------------------------------------
  // Sequential Timeout Counting Logic (Exact-N Threshold Semantics)
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      count_q         <= 32'd0;
      timeout_event   <= 1'b0;
      timeout_fired_q <= 1'b0;
    end else begin
      // Default: single-cycle pulse
      timeout_event <= 1'b0;

      if (timeout_limit == 32'd0) begin
        // Timeout disabled: counter cleared, no event generated
        count_q         <= 32'd0;
        timeout_fired_q <= 1'b0;
      end else if (stretch_active) begin
        if (!timeout_fired_q) begin
          if (count_q + 1'b1 == timeout_limit) begin
            // Exact N-th consecutive qualifying cycle reached
            count_q         <= count_q + 1'b1;
            timeout_event   <= 1'b1;
            timeout_fired_q <= 1'b1;
          end else begin
            count_q <= count_q + 1'b1;
          end
        end else begin
          // Maintain count while stretching continues; event fires only once per episode
          count_q <= count_q;
        end
      end else begin
        // Episode ended: physical SCL rose HIGH or master pulled SCL LOW
        count_q         <= 32'd0;
        timeout_fired_q <= 1'b0;
      end
    end
  end

endmodule : i2c_timeout
