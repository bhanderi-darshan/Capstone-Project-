// ============================================================================
// File:        i2c_master.sv
// Project:     AHB-Lite to I2C Master Controller
// Description: Master Controller FSM handling 7-bit addressing, START/STOP/
//              Repeated START generation, multi-byte transactions, single-byte
//              read with master NACK, NACK abort recovery, safe glitchless SCL
//              ownership handover, and bus-busy rejection.
// Standard:    SystemVerilog IEEE 1800-2012 (Synthesizable)
// ============================================================================

`timescale 1ns / 1ps

import i2c_pkg::*;

module i2c_master (
    input  logic        clk,                // 100 MHz System Clock (HCLK)
    input  logic        rst_n,              // Active-Low Reset

    // Command Strobes from i2c_registers (1-cycle pulses)
    input  logic        cmd_start_i,        // Generate START condition
    input  logic        cmd_write_i,        // Transmit byte
    input  logic        cmd_read_i,         // Receive byte
    input  logic        cmd_stop_i,         // Generate STOP condition
    input  logic        cmd_restart_i,      // Generate Repeated START

    // Configuration Inputs from i2c_registers
    input  logic        ctrl_enable_i,      // Controller Enable (CONTROL[0])
    input  logic        ctrl_auto_stop_i,   // Auto STOP after byte (CONTROL[2])
    input  logic [15:0] clk_high_count_i,   // SCL HIGH period in HCLK cycles
    input  logic [15:0] clk_low_count_i,    // SCL LOW period in HCLK cycles
    input  logic [31:0] timeout_limit_i,    // Clock-stretching timeout limit (TIMEOUT[31:0])
    input  logic [7:0]  tx_data_i,          // Transmit data byte (TX_DATA[7:0])

    // Hardware Status & Data Outputs to i2c_registers
    output logic        hw_busy_o,          // 1 = Active transaction (STATUS[0])
    output logic        hw_tx_empty_o,      // 1 = TX holding empty (STATUS[1])
    output logic        hw_rx_valid_o,      // 1-cycle pulse: RX valid (STATUS[2])
    output logic        hw_ack_error_o,     // 1-cycle pulse: NACK error (STATUS[3])
    output logic        hw_timeout_error_o, // 1-cycle pulse: Timeout (STATUS[4], Task D)
    output logic        hw_done_o,          // 1-cycle pulse: Command complete (STATUS[5])
    output logic [7:0]  hw_rx_data_o,       // Received data byte (RX_DATA[7:0])

    // Physical Bus Interface (Open-Drain Controls & Synchronized Inputs)
    input  logic        scl_in,             // Synchronized physical SCL bus input
    input  logic        sda_in,             // Synchronized physical SDA bus input
    output logic        scl_drive_low_o,    // 1 = Pull SCL LOW, 0 = Release (Open-Drain)
    output logic        sda_drive_low_o     // 1 = Pull SDA LOW, 0 = Release (Open-Drain)
);

  // --------------------------------------------------------------------------
  // Internal FSM State Machine
  // --------------------------------------------------------------------------
  i2c_state_t state_q;

  // Sub-phase counter for multi-step framing (START, RESTART, STOP)
  logic [2:0]  sub_phase_q;
  logic [15:0] timing_cnt_q;

  // --------------------------------------------------------------------------
  // Synthesizable 2-Stage Bus Input Synchronizers
  // --------------------------------------------------------------------------
  logic [1:0] scl_sync_q;
  logic [1:0] sda_sync_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      scl_sync_q <= 2'b11;
      sda_sync_q <= 2'b11;
    end else begin
      scl_sync_q <= {scl_sync_q[0], scl_in};
      sda_sync_q <= {sda_sync_q[0], sda_in};
    end
  end

  wire scl_sync = scl_sync_q[1];
  wire sda_sync = sda_sync_q[1];

  // --------------------------------------------------------------------------
  // Registered Status and Control Flags
  // --------------------------------------------------------------------------
  logic        tx_empty_q;
  logic        is_addr_phase_q;
  logic        abort_active_q;
  logic        nack_detected_q;

  assign hw_tx_empty_o = tx_empty_q;

  // --------------------------------------------------------------------------
  // Hardware Clock-Stretching Timeout (Task D)
  // --------------------------------------------------------------------------
  logic timeout_event;
  logic stretch_active;
  wire  scl_released = ~scl_drive_low_o & (state_q != ST_IDLE);

  i2c_timeout u_timeout (
      .clk           (clk),
      .reset_n       (rst_n),
      .scl_released  (scl_released),
      .scl_in        (scl_sync),
      .timeout_limit (timeout_limit_i),
      .timeout_event (timeout_event),
      .stretch_active(stretch_active)
  );

  assign hw_timeout_error_o = timeout_event;
  wire   cg_abort           = timeout_event;

  // --------------------------------------------------------------------------
  // Shift Registers & Bit Counter
  // --------------------------------------------------------------------------
  logic [7:0]  tx_shift_reg_q;
  logic [7:0]  rx_shift_reg_q;
  logic [2:0]  bit_cnt_q;
  logic [15:0] sample_cnt_q;
  logic        sample_done_q;

  // --------------------------------------------------------------------------
  // Zero-Count Clamping
  // --------------------------------------------------------------------------
  wire [15:0] clamped_low  = (clk_low_count_i  == 16'd0) ? 16'd1 : clk_low_count_i;
  wire [15:0] clamped_high = (clk_high_count_i == 16'd0) ? 16'd1 : clk_high_count_i;
  wire [15:0] sample_mid   = (clamped_high >> 1);

  // --------------------------------------------------------------------------
  // Bus-Free Qualification Counter (Continuous in ST_IDLE)
  // --------------------------------------------------------------------------
  logic [15:0] bus_free_cnt_q;
  wire         bus_is_free = (bus_free_cnt_q >= clamped_low);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bus_free_cnt_q <= 16'd0;
    end else begin
      if (state_q == ST_IDLE) begin
        if (scl_sync && sda_sync) begin
          if (bus_free_cnt_q < clamped_low)
            bus_free_cnt_q <= bus_free_cnt_q + 1'b1;
        end else begin
          bus_free_cnt_q <= 16'd0;
        end
      end else begin
        bus_free_cnt_q <= 16'd0;
      end
    end
  end

  // --------------------------------------------------------------------------
  // Clock Generator (Task B) Interface & Instantiation
  // --------------------------------------------------------------------------
  logic        cg_start_cycle_q;
  logic        cg_scl_drive_low;
  logic        cg_busy;
  logic        cg_cycle_done;
  logic        cg_stretch_wait;

  i2c_clock_gen u_clock_gen (
      .clk          (clk),
      .reset_n      (rst_n),
      .start_cycle  (cg_start_cycle_q),
      .high_count   (clk_high_count_i),
      .low_count    (clk_low_count_i),
      .scl_in       (scl_sync),
      .abort        (cg_abort),
      .scl_drive_low(cg_scl_drive_low),
      .busy         (cg_busy),
      .cycle_done   (cg_cycle_done),
      .stretch_wait (cg_stretch_wait)
  );

  // --------------------------------------------------------------------------
  // SCL & SDA Ownership & Drive Multiplexing
  // --------------------------------------------------------------------------
  logic fsm_scl_drive_low;
  logic scl_owner_cg_q;
  logic handover_overlap_q;

  logic fsm_sda_drive_low;
  logic sda_owner_byte_q;
  logic byte_sda_drive_low;

  assign scl_drive_low_o = fsm_scl_drive_low | (scl_owner_cg_q & cg_scl_drive_low);
  assign sda_drive_low_o = fsm_sda_drive_low | (sda_owner_byte_q & byte_sda_drive_low);

  // --------------------------------------------------------------------------
  // Midpoint SCL HIGH Sampling Logic (for ACK and Read Data)
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sample_cnt_q  <= 16'd0;
      sample_done_q <= 1'b0;
    end else begin
      if (cg_busy && scl_sync && !cg_stretch_wait && !cg_scl_drive_low) begin
        if (!sample_done_q) begin
          if (sample_cnt_q < sample_mid) begin
            sample_cnt_q <= sample_cnt_q + 1'b1;
          end else begin
            sample_done_q <= 1'b1;
          end
        end
      end else begin
        sample_cnt_q  <= 16'd0;
        sample_done_q <= 1'b0;
      end
    end
  end

  // Strobe indicating exact midpoint sampling cycle
  wire sample_mid_strobe = cg_busy && scl_sync && !cg_stretch_wait && !cg_scl_drive_low &&
                           !sample_done_q && (sample_cnt_q >= sample_mid);

  // --------------------------------------------------------------------------
  // Main Master FSM Sequential Process
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q           <= ST_IDLE;
      sub_phase_q       <= 3'd0;
      timing_cnt_q      <= 16'd0;
      tx_empty_q        <= 1'b1;
      is_addr_phase_q   <= 1'b0;
      abort_active_q    <= 1'b0;
      nack_detected_q   <= 1'b0;
      tx_shift_reg_q    <= 8'h00;
      rx_shift_reg_q    <= 8'h00;
      bit_cnt_q         <= 3'd0;
      hw_busy_o         <= 1'b0;
      hw_rx_valid_o     <= 1'b0;
      hw_ack_error_o    <= 1'b0;
      hw_done_o         <= 1'b0;
      hw_rx_data_o      <= 8'h00;
      cg_start_cycle_q  <= 1'b0;
      fsm_scl_drive_low <= 1'b0;
      scl_owner_cg_q    <= 1'b0;
      handover_overlap_q<= 1'b0;
      fsm_sda_drive_low <= 1'b0;
      sda_owner_byte_q  <= 1'b0;
      byte_sda_drive_low<= 1'b0;
    end else if (timeout_event) begin
      // ----------------------------------------------------------------------
      // Hardware Clock-Stretching Timeout Abort Sequence (Task D)
      // ----------------------------------------------------------------------
      state_q           <= ST_IDLE;
      sub_phase_q       <= 3'd0;
      timing_cnt_q      <= 16'd0;
      tx_empty_q        <= 1'b1;
      is_addr_phase_q   <= 1'b0;
      abort_active_q    <= 1'b0;
      nack_detected_q   <= 1'b0;
      tx_shift_reg_q    <= 8'h00;
      rx_shift_reg_q    <= 8'h00;
      bit_cnt_q         <= 3'd0;
      hw_busy_o         <= 1'b0;
      hw_done_o         <= 1'b0;
      hw_rx_valid_o     <= 1'b0;
      hw_ack_error_o    <= 1'b0;
      cg_start_cycle_q  <= 1'b0;
      fsm_scl_drive_low <= 1'b0; // Immediately release SCL
      scl_owner_cg_q    <= 1'b0;
      handover_overlap_q<= 1'b0;
      fsm_sda_drive_low <= 1'b0; // Immediately release SDA
      sda_owner_byte_q  <= 1'b0;
      byte_sda_drive_low<= 1'b0;
    end else begin
      // Default 1-cycle pulse clearing
      hw_done_o        <= 1'b0;
      hw_rx_valid_o    <= 1'b0;
      hw_ack_error_o   <= 1'b0;
      cg_start_cycle_q <= 1'b0;

      case (state_q)
        // --------------------------------------------------------------------
        // ST_IDLE: Bus is released, waiting for START
        // --------------------------------------------------------------------
        ST_IDLE: begin
          hw_busy_o         <= 1'b0;
          tx_empty_q        <= 1'b1;
          fsm_scl_drive_low <= 1'b0; // Release SCL
          scl_owner_cg_q    <= 1'b0;
          fsm_sda_drive_low <= 1'b0; // Release SDA
          sda_owner_byte_q  <= 1'b0;
          abort_active_q    <= 1'b0;
          nack_detected_q   <= 1'b0;
          sub_phase_q       <= 3'd0;
          timing_cnt_q      <= 16'd0;

          if (ctrl_enable_i && cmd_start_i) begin
            if (bus_is_free) begin
              hw_busy_o         <= 1'b1;
              fsm_sda_drive_low <= 1'b1; // Pull SDA LOW while SCL is HIGH
              timing_cnt_q      <= 16'd1;
              sub_phase_q       <= 3'd0;
              state_q           <= ST_START;
            end else begin
              // Bus occupied: reject request without pulling lines
              state_q <= ST_IDLE;
            end
          end
        end

        // --------------------------------------------------------------------
        // ST_START: Generate START framing
        // --------------------------------------------------------------------
        ST_START: begin
          hw_busy_o <= 1'b1;
          case (sub_phase_q)
            // Phase 0: SDA pulled LOW, SCL HIGH -> wait t_HD;STA (high_count)
            3'd0: begin
              fsm_sda_drive_low <= 1'b1;
              fsm_scl_drive_low <= 1'b0;
              if (!scl_sync) begin
                // Physical SCL is LOW: freeze timing counter (stretching / fault)
                timing_cnt_q <= 16'd1;
              end else begin
                if (timing_cnt_q < clamped_high) begin
                  timing_cnt_q <= timing_cnt_q + 1'b1;
                end else begin
                  // t_HD;STA elapsed: pull SCL LOW
                  fsm_scl_drive_low <= 1'b1;
                  timing_cnt_q      <= 16'd1;
                  sub_phase_q       <= 3'd1;
                end
              end
            end

            // Phase 1: SCL pulled LOW -> wait t_LOW_HOLD (low_count)
            3'd1: begin
              fsm_sda_drive_low <= 1'b1;
              fsm_scl_drive_low <= 1'b1;
              if (timing_cnt_q < clamped_low) begin
                timing_cnt_q <= timing_cnt_q + 1'b1;
              end else begin
                // START complete: release SDA, hold SCL LOW, enter CMD_READY
                fsm_sda_drive_low <= 1'b0;
                fsm_scl_drive_low <= 1'b1; // SCL clamped LOW in CMD_READY
                hw_done_o         <= 1'b1;
                is_addr_phase_q   <= 1'b1;
                tx_empty_q        <= 1'b1;
                state_q           <= ST_CMD_READY;
              end
            end

            default: state_q <= ST_IDLE;
          endcase
        end

        // --------------------------------------------------------------------
        // ST_CMD_READY: Bus owned (SCL held LOW), waiting for next command
        // --------------------------------------------------------------------
        ST_CMD_READY: begin
          hw_busy_o         <= 1'b1;
          fsm_scl_drive_low <= 1'b1; // Maintain SCL held LOW
          scl_owner_cg_q    <= 1'b0;
          fsm_sda_drive_low <= 1'b0; // Release SDA
          sda_owner_byte_q  <= 1'b0;
          sub_phase_q       <= 3'd0;
          timing_cnt_q      <= 16'd0;

          if (cmd_write_i) begin
            tx_shift_reg_q     <= tx_data_i;
            bit_cnt_q          <= 3'd7;
            tx_empty_q         <= 1'b0;
            byte_sda_drive_low <= ~tx_data_i[7]; // Setup MSB on SDA
            sda_owner_byte_q   <= 1'b1;
            scl_owner_cg_q     <= 1'b1; // Transfer SCL control to clock gen
            fsm_scl_drive_low  <= 1'b1; // Keep SCL clamped LOW during transition cycle
            handover_overlap_q <= 1'b1; // Hold SCL LOW 1 overlapping cycle into byte state
            cg_start_cycle_q   <= 1'b1; // Trigger first SCL clock cycle

            if (is_addr_phase_q) begin
              is_addr_phase_q <= 1'b0;
              state_q         <= ST_ADDR;
            end else begin
              state_q         <= ST_WRITE;
            end
          end else if (cmd_read_i) begin
            bit_cnt_q          <= 3'd7;
            sda_owner_byte_q   <= 1'b0; // Master releases SDA for read
            scl_owner_cg_q     <= 1'b1;
            fsm_scl_drive_low  <= 1'b1; // Keep SCL clamped LOW during transition cycle
            handover_overlap_q <= 1'b1; // Hold SCL LOW 1 overlapping cycle into byte state
            cg_start_cycle_q   <= 1'b1;
            state_q            <= ST_READ;
          end else if (cmd_restart_i) begin
            timing_cnt_q      <= 16'd1;
            sub_phase_q       <= 3'd0;
            fsm_scl_drive_low <= 1'b1;
            scl_owner_cg_q    <= 1'b0;
            sda_owner_byte_q  <= 1'b0;
            state_q           <= ST_RESTART;
          end else if (cmd_stop_i) begin
            timing_cnt_q      <= 16'd1;
            sub_phase_q       <= 3'd0;
            fsm_scl_drive_low <= 1'b1;
            scl_owner_cg_q    <= 1'b0;
            sda_owner_byte_q  <= 1'b0;
            state_q           <= ST_STOP;
          end
        end

        // --------------------------------------------------------------------
        // ST_ADDR: Transmit 8-bit Address + R/W
        // --------------------------------------------------------------------
        ST_ADDR: begin
          hw_busy_o          <= 1'b1;
          scl_owner_cg_q     <= 1'b1;
          if (handover_overlap_q) begin
            fsm_scl_drive_low  <= 1'b1;
            handover_overlap_q <= 1'b0;
          end else begin
            fsm_scl_drive_low  <= 1'b0;
          end
          sda_owner_byte_q   <= 1'b1;
          byte_sda_drive_low <= ~tx_shift_reg_q[7];

          if (cg_cycle_done) begin
            if (bit_cnt_q > 3'd0) begin
              bit_cnt_q          <= bit_cnt_q - 1'b1;
              tx_shift_reg_q     <= {tx_shift_reg_q[6:0], 1'b0};
              byte_sda_drive_low <= ~tx_shift_reg_q[6];
              cg_start_cycle_q   <= 1'b1; // Trigger next bit
            end else begin
              // 8 bits finished: prepare for ACK (release SDA)
              sda_owner_byte_q <= 1'b0;
              cg_start_cycle_q <= 1'b1; // Trigger 9th clock cycle
              nack_detected_q  <= 1'b0;
              state_q          <= ST_ADDR_ACK;
            end
          end
        end

        // --------------------------------------------------------------------
        // ST_ADDR_ACK: 9th clock cycle for Address ACK/NACK
        // --------------------------------------------------------------------
        ST_ADDR_ACK: begin
          hw_busy_o         <= 1'b1;
          scl_owner_cg_q    <= 1'b1;
          fsm_scl_drive_low <= 1'b0;
          sda_owner_byte_q  <= 1'b0; // Master floats SDA

          if (sample_mid_strobe) begin
            nack_detected_q <= sda_sync; // 0 = ACK, 1 = NACK
          end

          if (cg_cycle_done) begin
            // Clock generator has pulled SCL LOW: safe handover
            scl_owner_cg_q    <= 1'b0;
            fsm_scl_drive_low <= 1'b1; // Clamp SCL LOW
            tx_empty_q        <= 1'b1;

            if (nack_detected_q || (sample_mid_strobe && sda_sync)) begin
              // Slave NACK on address: abort
              hw_ack_error_o   <= 1'b1;
              abort_active_q   <= 1'b1;
              sda_owner_byte_q <= 1'b0;
              timing_cnt_q     <= 16'd1;
              sub_phase_q      <= 3'd0;
              state_q          <= ST_STOP;
            end else begin
              // Slave ACK received: AUTO_STOP is ignored on Address
              hw_done_o <= 1'b1;
              state_q   <= ST_CMD_READY;
            end
          end
        end

        // --------------------------------------------------------------------
        // ST_WRITE: Transmit 8-bit Data
        // --------------------------------------------------------------------
        ST_WRITE: begin
          hw_busy_o          <= 1'b1;
          scl_owner_cg_q     <= 1'b1;
          if (handover_overlap_q) begin
            fsm_scl_drive_low  <= 1'b1;
            handover_overlap_q <= 1'b0;
          end else begin
            fsm_scl_drive_low  <= 1'b0;
          end
          sda_owner_byte_q   <= 1'b1;
          byte_sda_drive_low <= ~tx_shift_reg_q[7];

          if (cg_cycle_done) begin
            if (bit_cnt_q > 3'd0) begin
              bit_cnt_q          <= bit_cnt_q - 1'b1;
              tx_shift_reg_q     <= {tx_shift_reg_q[6:0], 1'b0};
              byte_sda_drive_low <= ~tx_shift_reg_q[6];
              cg_start_cycle_q   <= 1'b1; // Trigger next bit
            end else begin
              // 8 data bits finished: prepare for ACK
              sda_owner_byte_q <= 1'b0;
              cg_start_cycle_q <= 1'b1; // Trigger 9th clock cycle
              nack_detected_q  <= 1'b0;
              state_q          <= ST_WRITE_ACK;
            end
          end
        end

        // --------------------------------------------------------------------
        // ST_WRITE_ACK: 9th clock cycle for Data ACK/NACK
        // --------------------------------------------------------------------
        ST_WRITE_ACK: begin
          hw_busy_o         <= 1'b1;
          scl_owner_cg_q    <= 1'b1;
          fsm_scl_drive_low <= 1'b0;
          sda_owner_byte_q  <= 1'b0; // Master floats SDA

          if (sample_mid_strobe) begin
            nack_detected_q <= sda_sync;
          end

          if (cg_cycle_done) begin
            scl_owner_cg_q    <= 1'b0;
            fsm_scl_drive_low <= 1'b1; // Clamp SCL LOW
            tx_empty_q        <= 1'b1;

            if (nack_detected_q || (sample_mid_strobe && sda_sync)) begin
              // Slave NACK on data: abort
              hw_ack_error_o   <= 1'b1;
              abort_active_q   <= 1'b1;
              sda_owner_byte_q <= 1'b0;
              timing_cnt_q     <= 16'd1;
              sub_phase_q      <= 3'd0;
              state_q          <= ST_STOP;
            end else begin
              // Data ACK received
              hw_done_o <= 1'b1;
              if (ctrl_auto_stop_i) begin
                timing_cnt_q     <= 16'd1;
                sub_phase_q      <= 3'd0;
                sda_owner_byte_q <= 1'b0;
                state_q          <= ST_STOP;
              end else begin
                state_q <= ST_CMD_READY;
              end
            end
          end
        end

        // --------------------------------------------------------------------
        // ST_READ: Receive 8-bit Data
        // --------------------------------------------------------------------
        ST_READ: begin
          hw_busy_o         <= 1'b1;
          scl_owner_cg_q    <= 1'b1;
          if (handover_overlap_q) begin
            fsm_scl_drive_low  <= 1'b1;
            handover_overlap_q <= 1'b0;
          end else begin
            fsm_scl_drive_low  <= 1'b0;
          end
          sda_owner_byte_q  <= 1'b0; // Master releases SDA for slave data

          if (sample_mid_strobe) begin
            rx_shift_reg_q <= {rx_shift_reg_q[6:0], sda_sync};
          end

          if (cg_cycle_done) begin
            if (bit_cnt_q > 3'd0) begin
              bit_cnt_q        <= bit_cnt_q - 1'b1;
              cg_start_cycle_q <= 1'b1; // Trigger next bit
            end else begin
              // 8 bits received: capture byte & pulse valid
              hw_rx_data_o     <= rx_shift_reg_q;
              hw_rx_valid_o    <= 1'b1;
              cg_start_cycle_q <= 1'b1; // Trigger 9th clock cycle for Master NACK
              state_q          <= ST_READ_ACK;
            end
          end
        end

        // --------------------------------------------------------------------
        // ST_READ_ACK: 9th clock cycle for Master NACK
        // --------------------------------------------------------------------
        ST_READ_ACK: begin
          hw_busy_o         <= 1'b1;
          scl_owner_cg_q    <= 1'b1;
          fsm_scl_drive_low <= 1'b0;
          sda_owner_byte_q  <= 1'b0;
          fsm_sda_drive_low <= 1'b0; // Master NACK (release SDA HIGH)

          if (cg_cycle_done) begin
            scl_owner_cg_q    <= 1'b0;
            fsm_scl_drive_low <= 1'b1; // Clamp SCL LOW
            hw_done_o         <= 1'b1;

            if (ctrl_auto_stop_i) begin
              timing_cnt_q     <= 16'd1;
              sub_phase_q      <= 3'd0;
              sda_owner_byte_q <= 1'b0;
              state_q          <= ST_STOP;
            end else begin
              state_q <= ST_CMD_READY;
            end
          end
        end

        // --------------------------------------------------------------------
        // ST_RESTART: Repeated START Framing
        // --------------------------------------------------------------------
        ST_RESTART: begin
          hw_busy_o        <= 1'b1;
          scl_owner_cg_q   <= 1'b0;
          sda_owner_byte_q <= 1'b0;

          case (sub_phase_q)
            // Phase 0: SCL held LOW, release SDA -> wait t_LOW_HOLD (low_count)
            3'd0: begin
              fsm_scl_drive_low <= 1'b1;
              fsm_sda_drive_low <= 1'b0;
              if (timing_cnt_q < clamped_low) begin
                timing_cnt_q <= timing_cnt_q + 1'b1;
              end else begin
                // Release SCL
                fsm_scl_drive_low <= 1'b0;
                timing_cnt_q      <= 16'd1;
                sub_phase_q       <= 3'd1;
              end
            end

            // Phase 1: Wait for scl_in == 1, then wait t_SU;STA (high_count)
            3'd1: begin
              fsm_scl_drive_low <= 1'b0;
              fsm_sda_drive_low <= 1'b0;
              if (!scl_sync) begin
                timing_cnt_q <= 16'd1; // Freeze counter while stretching
              end else begin
                if (timing_cnt_q < clamped_high) begin
                  timing_cnt_q <= timing_cnt_q + 1'b1;
                end else begin
                  // Pull SDA LOW while SCL is HIGH -> Repeated START edge!
                  fsm_sda_drive_low <= 1'b1;
                  timing_cnt_q      <= 16'd1;
                  sub_phase_q       <= 3'd2;
                end
              end
            end

            // Phase 2: SDA pulled LOW, SCL HIGH -> wait t_HD;STA (high_count)
            3'd2: begin
              fsm_scl_drive_low <= 1'b0;
              fsm_sda_drive_low <= 1'b1;
              if (timing_cnt_q < clamped_high) begin
                timing_cnt_q <= timing_cnt_q + 1'b1;
              end else begin
                // Pull SCL LOW
                fsm_scl_drive_low <= 1'b1;
                timing_cnt_q      <= 16'd1;
                sub_phase_q       <= 3'd3;
              end
            end

            // Phase 3: SCL held LOW -> wait t_LOW_HOLD (low_count)
            3'd3: begin
              fsm_scl_drive_low <= 1'b1;
              fsm_sda_drive_low <= 1'b1;
              if (timing_cnt_q < clamped_low) begin
                timing_cnt_q <= timing_cnt_q + 1'b1;
              end else begin
                fsm_sda_drive_low <= 1'b0;
                fsm_scl_drive_low <= 1'b1; // SCL clamped LOW in CMD_READY
                hw_done_o         <= 1'b1;
                is_addr_phase_q   <= 1'b1;
                tx_empty_q        <= 1'b1;
                state_q           <= ST_CMD_READY;
              end
            end

            default: state_q <= ST_IDLE;
          endcase
        end

        // --------------------------------------------------------------------
        // ST_STOP: Generate STOP framing
        // --------------------------------------------------------------------
        ST_STOP: begin
          hw_busy_o        <= 1'b1;
          scl_owner_cg_q   <= 1'b0;
          sda_owner_byte_q <= 1'b0;

          case (sub_phase_q)
            // Phase 0: SCL held LOW, pull SDA LOW -> wait t_LOW_HOLD (low_count)
            3'd0: begin
              fsm_scl_drive_low <= 1'b1;
              fsm_sda_drive_low <= 1'b1;
              if (timing_cnt_q < clamped_low) begin
                timing_cnt_q <= timing_cnt_q + 1'b1;
              end else begin
                // Release SCL
                fsm_scl_drive_low <= 1'b0;
                timing_cnt_q      <= 16'd1;
                sub_phase_q       <= 3'd1;
              end
            end

            // Phase 1: SCL released, SDA LOW -> wait for scl_in==1, wait t_SU;STO (high_count)
            3'd1: begin
              fsm_scl_drive_low <= 1'b0;
              fsm_sda_drive_low <= 1'b1;
              if (!scl_sync) begin
                timing_cnt_q <= 16'd1; // Freeze counter while stretching
              end else begin
                if (timing_cnt_q < clamped_high) begin
                  timing_cnt_q <= timing_cnt_q + 1'b1;
                end else begin
                  // Release SDA while SCL is HIGH -> Valid STOP edge!
                  fsm_sda_drive_low <= 1'b0;
                  timing_cnt_q      <= 16'd1;
                  sub_phase_q       <= 3'd2;
                end
              end
            end

            // Phase 2: SCL HIGH, SDA HIGH -> wait bus-free time t_BUF (low_count)
            3'd2: begin
              fsm_scl_drive_low <= 1'b0;
              fsm_sda_drive_low <= 1'b0;
              if (timing_cnt_q < clamped_low) begin
                timing_cnt_q <= timing_cnt_q + 1'b1;
              end else begin
                // STOP framing completed
                if (!abort_active_q) begin
                  hw_done_o <= 1'b1;
                end
                abort_active_q    <= 1'b0;
                hw_busy_o         <= 1'b0;
                tx_empty_q        <= 1'b1;
                fsm_scl_drive_low <= 1'b0;
                fsm_sda_drive_low <= 1'b0;
                state_q           <= ST_IDLE;
              end
            end

            default: state_q <= ST_IDLE;
          endcase
        end

        default: begin
          state_q           <= ST_IDLE;
          fsm_scl_drive_low <= 1'b0;
          fsm_sda_drive_low <= 1'b0;
          scl_owner_cg_q    <= 1'b0;
          sda_owner_byte_q  <= 1'b0;
          hw_busy_o         <= 1'b0;
          tx_empty_q        <= 1'b1;
        end
      endcase
    end
  end

endmodule : i2c_master
