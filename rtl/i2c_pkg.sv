// ============================================================================
// File:        i2c_pkg.sv
// Project:     AHB-Lite to I2C Master Controller
// Description: Package containing global definitions, register offsets,
//              bit field masks, and FSM enumerated states.
// Standard:    SystemVerilog IEEE 1800-2012
// ============================================================================

package i2c_pkg;

  // --------------------------------------------------------------------------
  // Register Offsets (Word-Aligned 32-bit Memory Map)
  // --------------------------------------------------------------------------
  localparam logic [7:0] ADDR_CONTROL   = 8'h00; // Controller Configuration
  localparam logic [7:0] ADDR_STATUS    = 8'h04; // Controller Status Flags
  localparam logic [7:0] ADDR_CLOCK_DIV = 8'h08; // SCL High/Low Counts
  localparam logic [7:0] ADDR_TX_DATA   = 8'h0C; // Transmit Data / Address
  localparam logic [7:0] ADDR_RX_DATA   = 8'h10; // Received Data Byte
  localparam logic [7:0] ADDR_COMMAND   = 8'h14; // Command Strobes
  localparam logic [7:0] ADDR_TIMEOUT   = 8'h18; // Stretch Timeout Limit
  localparam logic [7:0] ADDR_IRQ       = 8'h1C; // Interrupt Status & Enable

  // --------------------------------------------------------------------------
  // CONTROL Register Bit Positions (0x00)
  // --------------------------------------------------------------------------
  localparam int CTRL_ENABLE_BIT     = 0; // Bit 0: Controller Enable
  localparam int CTRL_INT_ENABLE_BIT = 1; // Bit 1: Global Interrupt Enable
  localparam int CTRL_AUTO_STOP_BIT  = 2; // Bit 2: Automatic STOP after byte

  // --------------------------------------------------------------------------
  // STATUS Register Bit Positions (0x04)
  // --------------------------------------------------------------------------
  localparam int STAT_BUSY_BIT          = 0; // Bit 0: I2C Core Busy
  localparam int STAT_TX_EMPTY_BIT      = 1; // Bit 1: TX Holding Register Empty
  localparam int STAT_RX_VALID_BIT      = 2; // Bit 2: RX Data Valid Available
  localparam int STAT_ACK_ERROR_BIT     = 3; // Bit 3: Slave NACK Detected
  localparam int STAT_TIMEOUT_ERROR_BIT = 4; // Bit 4: Clock Stretch Timeout
  localparam int STAT_DONE_BIT          = 5; // Bit 5: Operation/Byte Completed

  // --------------------------------------------------------------------------
  // COMMAND Register Bit Positions (0x14) - Write-Only Strobes
  // --------------------------------------------------------------------------
  localparam int CMD_START_BIT   = 0; // Bit 0: Issue START condition
  localparam int CMD_WRITE_BIT   = 1; // Bit 1: Issue Byte Write
  localparam int CMD_READ_BIT    = 2; // Bit 2: Issue Byte Read
  localparam int CMD_STOP_BIT    = 3; // Bit 3: Issue STOP condition
  localparam int CMD_RESTART_BIT = 4; // Bit 4: Issue Repeated START

  // --------------------------------------------------------------------------
  // IRQ Register Bit Positions (0x1C)
  // --------------------------------------------------------------------------
  localparam int IRQ_DONE_PENDING_BIT      = 0;  // Bit 0: Done Pending (W1C)
  localparam int IRQ_ACK_ERROR_PENDING_BIT = 1;  // Bit 1: ACK Error Pending (W1C)
  localparam int IRQ_TIMEOUT_PENDING_BIT   = 2;  // Bit 2: Timeout Pending (W1C)
  localparam int IRQ_DONE_ENABLE_BIT       = 8;  // Bit 8: Done Interrupt Enable
  localparam int IRQ_ACK_ERROR_ENABLE_BIT  = 9;  // Bit 9: ACK Error Int Enable
  localparam int IRQ_TIMEOUT_ENABLE_BIT    = 10; // Bit 10: Timeout Int Enable

  // --------------------------------------------------------------------------
  // Default Reset Constants (for 100 MHz HCLK)
  // --------------------------------------------------------------------------
  // 100 kHz Standard Mode default: 500 cycles High (5 us), 500 cycles Low (5 us)
  localparam logic [15:0] DEFAULT_HIGH_COUNT = 16'd500;
  localparam logic [15:0] DEFAULT_LOW_COUNT  = 16'd500;
  localparam logic [31:0] DEFAULT_CLOCK_DIV  = {DEFAULT_LOW_COUNT, DEFAULT_HIGH_COUNT};
  // Default timeout: 100,000 cycles = 1 ms at 100 MHz
  localparam logic [31:0] DEFAULT_TIMEOUT    = 32'd100000;

  // --------------------------------------------------------------------------
  // I2C Protocol FSM States (12 States defined in project doc)
  // --------------------------------------------------------------------------
  typedef enum logic [4:0] {
    ST_IDLE      = 5'd0,
    ST_START     = 5'd1,
    ST_ADDR      = 5'd2,
    ST_ADDR_ACK  = 5'd3,
    ST_WRITE     = 5'd4,
    ST_WRITE_ACK = 5'd5,
    ST_READ      = 5'd6,
    ST_READ_ACK  = 5'd7,
    ST_RESTART   = 5'd8,
    ST_STOP      = 5'd9,
    ST_DONE      = 5'd10,
    ST_ERROR     = 5'd11,
    ST_CMD_READY = 5'd12
  } i2c_state_t;

endpackage : i2c_pkg
