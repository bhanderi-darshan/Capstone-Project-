// ============================================================================
// File:        i2c_clock_gen.sv
// Project:     AHB-Lite to I2C Master Controller
// Description: Programmable I2C SCL Clock Generator with Hardware Clock-
//              Stretching support and independent HIGH and LOW phase counters.
//              Generates a single controlled SCL cycle on request.
// Standard:    SystemVerilog IEEE 1800-2012 (Synthesizable)
// ============================================================================

`timescale 1ns / 1ps

module i2c_clock_gen (
    input  logic        clk,           // 100 MHz System Clock (HCLK, 10 ns)
    input  logic        reset_n,       // Active-Low Reset

    input  logic        start_cycle,   // 1-cycle request to generate one SCL clock cycle
    input  logic [15:0] high_count,    // SCL HIGH duration in HCLK cycles
    input  logic [15:0] low_count,     // SCL LOW duration in HCLK cycles

    input  logic        scl_in,        // Synchronized physical SCL bus input
    input  logic        abort,         // Synchronous abort strobe to immediately restore IDLE

    output logic        scl_drive_low, // 1 = Pull SCL LOW, 0 = Release SCL (Open-Drain)
    output logic        busy,          // 1 = Clock generator active
    output logic        cycle_done,    // 1-cycle completion pulse
    output logic        stretch_wait   // 1 = Waiting for physical SCL to rise
);

  // --------------------------------------------------------------------------
  // State Machine Definition
  // --------------------------------------------------------------------------
  typedef enum logic [2:0] {
    STATE_IDLE          = 3'b000,
    STATE_SCL_LOW       = 3'b001,
    STATE_WAIT_SCL_HIGH = 3'b010,
    STATE_SCL_HIGH      = 3'b011,
    STATE_CYCLE_DONE    = 3'b100
  } clk_gen_state_t;

  clk_gen_state_t state_q;

  // --------------------------------------------------------------------------
  // Internal Timing Registers & Clamping
  // --------------------------------------------------------------------------
  logic [15:0] count_q;
  logic [15:0] eff_low_count_q;
  logic [15:0] eff_high_count_q;

  // Zero-count hardware clamping: A value of 0 is safely clamped to 1 HCLK cycle (10 ns)
  wire [15:0] clamped_low  = (low_count  == 16'd0) ? 16'd1 : low_count;
  wire [15:0] clamped_high = (high_count == 16'd0) ? 16'd1 : high_count;

  // --------------------------------------------------------------------------
  // Sequential FSM & Counter Logic
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      state_q          <= STATE_IDLE;
      scl_drive_low    <= 1'b0; // Release SCL at reset (bus free / IDLE)
      busy             <= 1'b0;
      cycle_done       <= 1'b0;
      stretch_wait     <= 1'b0;
      count_q          <= 16'd0;
      eff_low_count_q  <= 16'd0;
      eff_high_count_q <= 16'd0;
    end else if (abort) begin
      state_q          <= STATE_IDLE;
      scl_drive_low    <= 1'b0; // Immediately release SCL on abort
      busy             <= 1'b0;
      cycle_done       <= 1'b0;
      stretch_wait     <= 1'b0;
      count_q          <= 16'd0;
      eff_low_count_q  <= 16'd0;
      eff_high_count_q <= 16'd0;
    end else begin
      case (state_q)
        // --------------------------------------------------------------------
        // IDLE: Wait for transaction request
        // --------------------------------------------------------------------
        STATE_IDLE: begin
          cycle_done   <= 1'b0;
          stretch_wait <= 1'b0;

          if (start_cycle) begin
            busy             <= 1'b1;
            scl_drive_low    <= 1'b1; // Pull SCL LOW for the first phase
            count_q          <= 16'd1;
            eff_low_count_q  <= clamped_low;
            eff_high_count_q <= clamped_high;
            state_q          <= STATE_SCL_LOW;
          end else begin
            busy <= 1'b0;
            // scl_drive_low retains its value: 1'b0 initially, or 1'b1 after a cycle
          end
        end

        // --------------------------------------------------------------------
        // SCL_LOW: Maintain SCL LOW for eff_low_count cycles
        // --------------------------------------------------------------------
        STATE_SCL_LOW: begin
          busy          <= 1'b1;
          scl_drive_low <= 1'b1;
          cycle_done    <= 1'b0;
          stretch_wait  <= 1'b0;

          if (count_q < eff_low_count_q) begin
            count_q <= count_q + 1'b1;
          end else begin
            // SCL LOW duration complete: release SCL
            scl_drive_low <= 1'b0;
            count_q       <= 16'd1;
            state_q       <= STATE_WAIT_SCL_HIGH;
          end
        end

        // --------------------------------------------------------------------
        // WAIT_SCL_HIGH: Monitor physical SCL input for clock stretching
        // --------------------------------------------------------------------
        STATE_WAIT_SCL_HIGH: begin
          busy          <= 1'b1;
          scl_drive_low <= 1'b0; // SCL remains released
          cycle_done    <= 1'b0;

          if (!scl_in) begin
            // Slave holds SCL LOW: hold in wait state
            stretch_wait <= 1'b1;
            count_q      <= 16'd1; // Freeze counter while stretching
          end else begin
            // Physical SCL is HIGH: stretch condition ended/absent
            stretch_wait <= 1'b0;

            if (eff_high_count_q == 16'd1) begin
              // High duration of 1 cycle is satisfied by the transition edge
              scl_drive_low <= 1'b1; // Pull SCL LOW at end of cycle
              cycle_done    <= 1'b1;
              state_q       <= STATE_CYCLE_DONE;
            end else begin
              count_q <= 16'd2; // First HIGH cycle elapsed; count remaining
              state_q <= STATE_SCL_HIGH;
            end
          end
        end

        // --------------------------------------------------------------------
        // SCL_HIGH: Maintain SCL HIGH for the remainder of eff_high_count
        // --------------------------------------------------------------------
        STATE_SCL_HIGH: begin
          busy          <= 1'b1;
          scl_drive_low <= 1'b0;
          cycle_done    <= 1'b0;
          stretch_wait  <= 1'b0;

          if (count_q < eff_high_count_q) begin
            count_q <= count_q + 1'b1;
          end else begin
            // SCL HIGH duration complete: pull SCL LOW again
            scl_drive_low <= 1'b1;
            cycle_done    <= 1'b1;
            state_q       <= STATE_CYCLE_DONE;
          end
        end

        // --------------------------------------------------------------------
        // CYCLE_DONE: Output 1-cycle completion pulse, hold SCL LOW
        // --------------------------------------------------------------------
        STATE_CYCLE_DONE: begin
          busy          <= 1'b0;
          scl_drive_low <= 1'b1; // Keep SCL held LOW between clock cycles
          cycle_done    <= 1'b0; // Pulse ends after exactly 1 cycle
          stretch_wait  <= 1'b0;
          state_q       <= STATE_IDLE;
        end

        default: begin
          state_q       <= STATE_IDLE;
          scl_drive_low <= 1'b0;
          busy          <= 1'b0;
          cycle_done    <= 1'b0;
          stretch_wait  <= 1'b0;
        end
      endcase
    end
  end

endmodule : i2c_clock_gen
