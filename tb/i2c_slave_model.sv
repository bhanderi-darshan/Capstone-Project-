// ============================================================================
// File:        i2c_slave_model.sv
// Project:     AHB-Lite to I2C Master Controller Verification
// Description: Synchronous, cycle-accurate I2C Slave BFM for Master verification.
//              Supports 7-bit addressing, programmable ACK/NACK responses,
//              clock stretching insertion, repeated START, and data transfers.
// Standard:    SystemVerilog IEEE 1800-2012
// ============================================================================

`timescale 1ns / 1ps

module i2c_slave_model #(
    parameter logic [6:0] SLAVE_ADDR = 7'h50
)(
    input  logic        clk,                // System clock for robust sampling
    input  logic        rst_n,

    // I2C Open-Drain Bus Pins
    input  logic        scl_in,
    output logic        scl_drive_low,

    input  logic        sda_in,
    output logic        sda_drive_low,

    // Testbench Control Inputs
    input  logic        force_addr_nack,
    input  logic        force_data_nack,
    input  logic        stretch_en,
    input  logic [31:0] stretch_duration_ns,
    input  logic [3:0]  stretch_on_bit,     // 0-7 = data bit
    input  logic [7:0]  tx_data_byte,       // Data byte returned on Master read

    // Status / Monitor Outputs
    output logic [6:0]  captured_addr,
    output logic        captured_rw,
    output logic [7:0]  captured_data,
    output logic        data_valid,
    output logic        start_seen,
    output logic        stop_seen
);

  typedef enum logic [2:0] {
    SLV_IDLE      = 3'd0,
    SLV_ADDR      = 3'd1,
    SLV_ADDR_ACK  = 3'd2,
    SLV_WRITE     = 3'd3,
    SLV_WRITE_ACK = 3'd4,
    SLV_READ      = 3'd5,
    SLV_READ_ACK  = 3'd6
  } slv_state_t;

  slv_state_t state_q;

  logic [7:0]  shift_q;
  logic [3:0]  bit_cnt_q;
  logic        is_matching_slave;

  // Sampling flops for edge detection
  logic scl_d1, scl_d2;
  logic sda_d1, sda_d2;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      scl_d1 <= 1'b1;
      scl_d2 <= 1'b1;
      sda_d1 <= 1'b1;
      sda_d2 <= 1'b1;
    end else begin
      scl_d1 <= scl_in;
      scl_d2 <= scl_d1;
      sda_d1 <= sda_in;
      sda_d2 <= sda_d1;
    end
  end

  wire scl_rise = (scl_d1 && !scl_d2);
  wire scl_fall = (!scl_d1 && scl_d2);
  wire sda_fall = (!sda_d1 && sda_d2);
  wire sda_rise = (sda_d1 && !sda_d2);

  // START: SDA falling while SCL is HIGH
  wire start_edge = sda_fall && scl_d1;
  // STOP: SDA rising while SCL is HIGH
  wire stop_edge  = sda_rise && scl_d1;

  // Clock stretching counter
  int unsigned stretch_cnt_q;
  wire [31:0] stretch_cycles = stretch_duration_ns / 10; // 10ns HCLK period

  // --------------------------------------------------------------------------
  // Main Slave Protocol State Machine
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q           <= SLV_IDLE;
      scl_drive_low     <= 1'b0;
      sda_drive_low     <= 1'b0;
      bit_cnt_q         <= 4'd0;
      shift_q           <= 8'h00;
      captured_addr     <= 7'h00;
      captured_rw       <= 1'b0;
      captured_data     <= 8'h00;
      is_matching_slave <= 1'b0;
      data_valid        <= 1'b0;
      start_seen        <= 1'b0;
      stop_seen         <= 1'b0;
      stretch_cnt_q     <= 0;
    end else begin
      data_valid <= 1'b0; // default 1-cycle pulse

      // STOP Condition Detection
      if (stop_edge) begin
        state_q           <= SLV_IDLE;
        scl_drive_low     <= 1'b0;
        sda_drive_low     <= 1'b0;
        stop_seen         <= 1'b1;
        start_seen        <= 1'b0;
        is_matching_slave <= 1'b0;
        bit_cnt_q         <= 4'd0;
      end
      // START / Repeated START Condition Detection
      else if (start_edge) begin
        state_q           <= SLV_ADDR;
        bit_cnt_q         <= 4'd0;
        shift_q           <= 8'h00;
        scl_drive_low     <= 1'b0;
        sda_drive_low     <= 1'b0;
        start_seen        <= 1'b1;
        stop_seen         <= 1'b0;
        is_matching_slave <= 1'b0;
      end
      else begin
        // Clock stretching execution
        if (scl_drive_low) begin
          if (!stretch_en) begin
            scl_drive_low <= 1'b0; // Immediate release when disabled by testbench
            stretch_cnt_q <= 0;
          end else if (stretch_cnt_q < stretch_cycles) begin
            stretch_cnt_q <= stretch_cnt_q + 1;
            scl_drive_low <= 1'b1;
          end else begin
            scl_drive_low <= 1'b0; // Release stretch
            stretch_cnt_q <= 0;
          end
        end

        case (state_q)
          // ------------------------------------------------------------------
          // SLV_IDLE
          // ------------------------------------------------------------------
          SLV_IDLE: begin
            scl_drive_low <= 1'b0;
            sda_drive_low <= 1'b0;
            bit_cnt_q     <= 4'd0;
          end

          // ------------------------------------------------------------------
          // SLV_ADDR: Receiving 7-bit Address + R/W
          // ------------------------------------------------------------------
          SLV_ADDR: begin
            if (scl_rise) begin
              shift_q   <= {shift_q[6:0], sda_d1};
              bit_cnt_q <= bit_cnt_q + 1'b1;
            end else if (scl_fall && (bit_cnt_q == 4'd8)) begin
              // 8 bits received: verify slave address
              captured_addr <= shift_q[7:1];
              captured_rw   <= shift_q[0];
              bit_cnt_q     <= 4'd0;
              if ((shift_q[7:1] == SLAVE_ADDR) && !force_addr_nack) begin
                is_matching_slave <= 1'b1;
                sda_drive_low     <= 1'b1; // Pull SDA LOW for ACK
                state_q           <= SLV_ADDR_ACK;
              end else begin
                is_matching_slave <= 1'b0;
                sda_drive_low     <= 1'b0; // NACK (release SDA)
                state_q           <= SLV_IDLE;
              end
            end
          end

          // ------------------------------------------------------------------
          // SLV_ADDR_ACK: Transmitting ACK for Address (9th clock cycle)
          // ------------------------------------------------------------------
          SLV_ADDR_ACK: begin
            if (scl_fall) begin
              sda_drive_low <= 1'b0; // Release SDA after ACK
              bit_cnt_q     <= 4'd0;
              if (captured_rw == 1'b0) begin
                state_q <= SLV_WRITE;
              end else begin
                // Read requested: set up MSB of transmit data
                shift_q       <= tx_data_byte;
                sda_drive_low <= ~tx_data_byte[7];
                state_q       <= SLV_READ;
              end
            end
          end

          // ------------------------------------------------------------------
          // SLV_WRITE: Receiving payload data byte from Master
          // ------------------------------------------------------------------
          SLV_WRITE: begin
            if (scl_rise) begin
              shift_q   <= {shift_q[6:0], sda_d1};
              bit_cnt_q <= bit_cnt_q + 1'b1;
            end else if (scl_fall) begin
              // Check if clock stretching should be inserted on this bit
              if (stretch_en && (bit_cnt_q == stretch_on_bit) && (stretch_cnt_q == 0)) begin
                scl_drive_low <= 1'b1;
                stretch_cnt_q <= 1;
              end

              if (bit_cnt_q == 4'd8) begin
                // 8 data bits received
                captured_data <= shift_q;
                data_valid    <= 1'b1;
                bit_cnt_q     <= 4'd0;
                if (!force_data_nack) begin
                  sda_drive_low <= 1'b1; // Pull SDA LOW for ACK
                end else begin
                  sda_drive_low <= 1'b0; // NACK
                end
                state_q <= SLV_WRITE_ACK;
              end
            end
          end

          // ------------------------------------------------------------------
          // SLV_WRITE_ACK: Transmitting ACK for data byte (9th clock cycle)
          // ------------------------------------------------------------------
          SLV_WRITE_ACK: begin
            if (scl_fall) begin
              sda_drive_low <= 1'b0; // Release SDA
              bit_cnt_q     <= 4'd0;
              state_q       <= SLV_WRITE; // Ready for subsequent bytes
            end
          end

          // ------------------------------------------------------------------
          // SLV_READ: Transmitting read data byte to Master
          // ------------------------------------------------------------------
          SLV_READ: begin
            if (scl_rise) begin
              bit_cnt_q <= bit_cnt_q + 1'b1;
            end else if (scl_fall) begin
              if (bit_cnt_q < 4'd8) begin
                sda_drive_low <= ~shift_q[7 - bit_cnt_q];
              end else begin
                // 8 bits sent: release SDA so Master can send ACK/NACK
                sda_drive_low <= 1'b0;
                bit_cnt_q     <= 4'd0;
                state_q       <= SLV_READ_ACK;
              end
            end
          end

          // ------------------------------------------------------------------
          // SLV_READ_ACK: Master sending ACK/NACK (9th clock cycle)
          // ------------------------------------------------------------------
          SLV_READ_ACK: begin
            if (scl_fall) begin
              sda_drive_low <= 1'b0;
              bit_cnt_q     <= 4'd0;
              state_q       <= SLV_IDLE; // Single-byte read ends
            end
          end

          default: state_q <= SLV_IDLE;
        endcase
      end
    end
  end

endmodule : i2c_slave_model
