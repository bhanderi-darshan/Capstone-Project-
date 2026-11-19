// ============================================================================
// File:        tb_i2c_master_top.sv
// Project:     AHB-Lite to I2C Master Controller Verification
// Description: Full-chip top-level self-checking SystemVerilog testbench for
//              i2c_master_top. Tests complete integration from AHB-Lite bus
//              cycles to physical I2C open-drain bus with slave BFM.
// Standard:    SystemVerilog IEEE 1800-2012
// ============================================================================

`timescale 1ns / 1ps

module tb_i2c_master_top;

  // --------------------------------------------------------------------------
  // Address Map & Register Constants
  // --------------------------------------------------------------------------
  localparam logic [31:0] ADDR_CONTROL   = 32'h00;
  localparam logic [31:0] ADDR_STATUS    = 32'h04;
  localparam logic [31:0] ADDR_CLOCK_DIV = 32'h08;
  localparam logic [31:0] ADDR_TX_DATA   = 32'h0C;
  localparam logic [31:0] ADDR_RX_DATA   = 32'h10;
  localparam logic [31:0] ADDR_COMMAND   = 32'h14;
  localparam logic [31:0] ADDR_TIMEOUT   = 32'h18;
  localparam logic [31:0] ADDR_IRQ       = 32'h1C;

  // Command Bitmasks (Write-Only Strobes)
  localparam logic [31:0] CMD_START   = 32'h00000001; // Bit 0
  localparam logic [31:0] CMD_WRITE   = 32'h00000002; // Bit 1
  localparam logic [31:0] CMD_READ    = 32'h00000004; // Bit 2
  localparam logic [31:0] CMD_STOP    = 32'h00000008; // Bit 3
  localparam logic [31:0] CMD_RESTART = 32'h00000010; // Bit 4

  // Status Bit Positions
  localparam int STAT_BUSY_BIT          = 0;
  localparam int STAT_TX_EMPTY_BIT      = 1;
  localparam int STAT_RX_VALID_BIT      = 2;
  localparam int STAT_ACK_ERROR_BIT     = 3;
  localparam int STAT_TIMEOUT_ERROR_BIT = 4;
  localparam int STAT_DONE_BIT          = 5;

  // --------------------------------------------------------------------------
  // Clock and Reset Signals (100 MHz HCLK, 10 ns period)
  // --------------------------------------------------------------------------
  logic HCLK;
  logic HRESETn;

  initial begin
    HCLK = 1'b0;
    forever #5 HCLK = ~HCLK; // 100 MHz clock
  end

  // --------------------------------------------------------------------------
  // AHB-Lite Master Interface Signals
  // --------------------------------------------------------------------------
  logic [31:0] HADDR;
  logic [31:0] HWDATA;
  logic        HWRITE;
  logic        HSEL;
  logic [1:0]  HTRANS;
  logic        HREADY;
  wire  [31:0] HRDATA;
  wire         HREADYOUT;
  wire         HRESP;

  // System Interrupt Line
  wire         irq_o;

  // --------------------------------------------------------------------------
  // Physical I2C Bus Signals with Pull-Up Resistors
  // --------------------------------------------------------------------------
  wire scl;
  wire sda;

  // Mandatory external pull-up resistors on open-drain lines
  pullup (scl);
  pullup (sda);

  // --------------------------------------------------------------------------
  // Slave Model & External Test Control Signals
  // --------------------------------------------------------------------------
  logic        slv_force_addr_nack;
  logic        slv_force_data_nack;
  logic        slv_stretch_en;
  logic [31:0] slv_stretch_duration_ns;
  logic [3:0]  slv_stretch_on_bit;
  logic [7:0]  slv_tx_data_byte;
  wire  [6:0]  slv_captured_addr;
  wire         slv_captured_rw;
  wire  [7:0]  slv_captured_data;
  wire         slv_data_valid;
  wire         slv_start_seen;
  wire         slv_stop_seen;

  logic        slv_scl_drive_low;
  logic        slv_sda_drive_low;

  // Slave open-drain line drives
  assign scl = slv_scl_drive_low ? 1'b0 : 1'bz;
  assign sda = slv_sda_drive_low ? 1'b0 : 1'bz;

  // --------------------------------------------------------------------------
  // DUT Instantiation: i2c_master_top
  // --------------------------------------------------------------------------
  i2c_master_top #(
      .ADDR_WIDTH (32),
      .DATA_WIDTH (32)
  ) dut (
      .HCLK      (HCLK),
      .HRESETn   (HRESETn),
      .HADDR     (HADDR),
      .HWDATA    (HWDATA),
      .HWRITE    (HWRITE),
      .HSEL      (HSEL),
      .HTRANS    (HTRANS),
      .HREADY    (HREADY),
      .HRDATA    (HRDATA),
      .HREADYOUT (HREADYOUT),
      .HRESP     (HRESP),
      .irq_o     (irq_o),
      .scl_io    (scl),
      .sda_io    (sda)
  );

  // --------------------------------------------------------------------------
  // Slave Model Instantiation: i2c_slave_model (7'h50)
  // --------------------------------------------------------------------------
  i2c_slave_model #(
      .SLAVE_ADDR (7'h50)
  ) u_slave (
      .clk                (HCLK),
      .rst_n              (HRESETn),
      .scl_in             (scl),
      .scl_drive_low      (slv_scl_drive_low),
      .sda_in             (sda),
      .sda_drive_low      (slv_sda_drive_low),
      .force_addr_nack    (slv_force_addr_nack),
      .force_data_nack    (slv_force_data_nack),
      .stretch_en         (slv_stretch_en),
      .stretch_duration_ns(slv_stretch_duration_ns),
      .stretch_on_bit     (slv_stretch_on_bit),
      .tx_data_byte       (slv_tx_data_byte),
      .captured_addr      (slv_captured_addr),
      .captured_rw        (slv_captured_rw),
      .captured_data      (slv_captured_data),
      .data_valid         (slv_data_valid),
      .start_seen         (slv_start_seen),
      .stop_seen          (slv_stop_seen)
  );

  // --------------------------------------------------------------------------
  // Verification Tracking & Assertion Framework
  // --------------------------------------------------------------------------
  int test_count = 0;
  int pass_count = 0;
  int fail_count = 0;

  task automatic check(input string test_name, input logic cond, input string detail);
    begin
      test_count++;
      if (cond) begin
        $display("  [PASS] Test %2d: %s -- %s", test_count, test_name, detail);
        pass_count++;
      end else begin
        $display("  [FAIL] Test %2d: %s -- %s", test_count, test_name, detail);
        fail_count++;
      end
    end
  endtask

  // --------------------------------------------------------------------------
  // AHB-Lite Driver Tasks (Pipelined Address and Data Phases)
  // --------------------------------------------------------------------------
  task automatic ahb_write_reg(input logic [31:0] addr, input logic [31:0] data);
    begin
      // Address Phase
      @(posedge HCLK);
      HSEL   <= 1'b1;
      HTRANS <= 2'b10; // NONSEQ
      HWRITE <= 1'b1;
      HADDR  <= addr;
      HREADY <= 1'b1;

      // Data Phase
      @(posedge HCLK);
      HWDATA <= data;
      HSEL   <= 1'b0;
      HTRANS <= 2'b00; // IDLE
      HWRITE <= 1'b0;
      HADDR  <= 32'h0;

      @(posedge HCLK);
      HWDATA <= 32'h0;
      #1; // Allow NBA updates in DUT to settle
    end
  endtask

  task automatic ahb_read_reg(input logic [31:0] addr, output logic [31:0] data);
    begin
      // Address Phase
      @(posedge HCLK);
      HSEL   <= 1'b1;
      HTRANS <= 2'b10; // NONSEQ
      HWRITE <= 1'b0;
      HADDR  <= addr;
      HREADY <= 1'b1;

      // Data Phase begins
      @(posedge HCLK);
      HSEL   <= 1'b0;
      HTRANS <= 2'b00; // IDLE
      HADDR  <= 32'h0;

      // Data Phase completes; sample HRDATA at clock edge
      @(posedge HCLK);
      data = HRDATA;
    end
  endtask

  // Bounded Polling Task for STATUS.DONE or ERROR with Timeout Guard
  task automatic wait_done_or_error(
      input  int          max_cycles,
      output logic [31:0] status_out,
      output logic        timed_out
  );
    int   cycles;
    logic loop_active;
    begin
      cycles      = 0;
      timed_out   = 1'b0;
      loop_active = 1'b1;
      while (loop_active) begin
        ahb_read_reg(ADDR_STATUS, status_out);
        cycles++;
        if (status_out[STAT_DONE_BIT] || 
            status_out[STAT_ACK_ERROR_BIT] || 
            status_out[STAT_TIMEOUT_ERROR_BIT]) begin
          loop_active = 1'b0;
        end else if (cycles >= max_cycles) begin
          timed_out   = 1'b1;
          loop_active = 1'b0;
        end else begin
          @(posedge HCLK);
        end
      end
    end
  endtask

  // Helper to ensure bus-free qualification time (t_BUF) is met before START
  task automatic wait_bus_free();
    begin
      // 250 HCLK cycles = 2500 ns (> 1300 ns Fast Mode t_BUF requirement)
      repeat (250) @(posedge HCLK);
    end
  endtask

  // --------------------------------------------------------------------------
  // Main Full-Chip Verification Process
  // --------------------------------------------------------------------------
  logic [31:0] rdata;
  logic [31:0] stat_val;
  logic        poll_timeout;
  int          abort_wait;

  initial begin
    $dumpfile("sim/tb_i2c_master_top.vcd");
    $dumpvars(0, tb_i2c_master_top);

    $display("============================================================================");
    $display("  STARTING TASK E STEP 3: FULL-CHIP SYSTEM VERIFICATION (i2c_master_top)    ");
    $display("============================================================================");

    // Initial signal states
    HRESETn                 = 1'b0;
    HADDR                   = 32'h0;
    HWDATA                  = 32'h0;
    HWRITE                  = 1'b0;
    HSEL                    = 1'b0;
    HTRANS                  = 2'b00;
    HREADY                  = 1'b1;
    slv_force_addr_nack     = 1'b0;
    slv_force_data_nack     = 1'b0;
    slv_stretch_en          = 1'b0;
    slv_stretch_duration_ns = 0;
    slv_stretch_on_bit      = 0;
    slv_tx_data_byte        = 8'h00;

    // Apply Hardware Reset (100 ns)
    #100;
    @(posedge HCLK);
    HRESETn = 1'b1;
    @(posedge HCLK);
    $display("[INFO] System reset deasserted. Physical lines: SCL=%b, SDA=%b", scl, sda);

    // ========================================================================
    // Scenario 1: Reset Values & Memory-Mapped Register Accesses
    // ========================================================================
    $display("\n--- SCENARIO 1: Reset & AHB Register Access Verification ---");
    ahb_read_reg(ADDR_CONTROL, rdata);
    check("Reset CONTROL", (rdata == 32'h0), $sformatf("Value = 0x%08X", rdata));

    ahb_read_reg(ADDR_STATUS, rdata);
    check("Reset STATUS (TX_EMPTY=1)", (rdata == 32'h00000002), $sformatf("Value = 0x%08X", rdata));

    ahb_read_reg(ADDR_CLOCK_DIV, rdata);
    check("Reset CLOCK_DIV (500/500)", (rdata == 32'h01F401F4), $sformatf("Value = 0x%08X", rdata));

    ahb_read_reg(ADDR_TIMEOUT, rdata);
    check("Reset TIMEOUT (100k cycles)", (rdata == 32'd100000), $sformatf("Value = 0x%08X", rdata));

    ahb_read_reg(ADDR_IRQ, rdata);
    check("Reset IRQ (0)", (rdata == 32'h0), $sformatf("Value = 0x%08X", rdata));

    // Register Write/Read Verification: Fast Mode (130 LOW, 120 HIGH = 250 cycles = 400 kHz)
    ahb_write_reg(ADDR_CLOCK_DIV, 32'h00820078);
    ahb_read_reg(ADDR_CLOCK_DIV, rdata);
    check("Write/Read CLOCK_DIV (400kHz)", (rdata == 32'h00820078), $sformatf("Value = 0x%08X", rdata));

    // Write/Read TX_DATA
    ahb_write_reg(ADDR_TX_DATA, 32'h000000A5);
    ahb_read_reg(ADDR_TX_DATA, rdata);
    check("Write/Read TX_DATA (0xA5)", (rdata[7:0] == 8'hA5), $sformatf("Value = 0x%02X", rdata[7:0]));

    // Unmapped Address Access: 0x30 returns 0, HRESP=0, registers uncorrupted
    ahb_write_reg(32'h00000030, 32'hFFFFFFFF);
    check("Unmapped Write HRESP OKAY", (HRESP == 1'b0), "HRESP is OKAY");
    ahb_read_reg(32'h00000030, rdata);
    check("Unmapped Read Returns 0", (rdata == 32'h0), $sformatf("Value = 0x%08X", rdata));
    ahb_read_reg(ADDR_TX_DATA, rdata);
    check("TX_DATA Uncorrupted", (rdata[7:0] == 8'hA5), "TX_DATA remains 0xA5");

    // ========================================================================
    // Scenario 2: Bus Idle & Open-Drain Verification
    // ========================================================================
    $display("\n--- SCENARIO 2: Open-Drain Physical Line Verification ---");
    check("SCL Floats HIGH in IDLE", (scl === 1'b1), "SCL line is 1 via pull-up");
    check("SDA Floats HIGH in IDLE", (sda === 1'b1), "SDA line is 1 via pull-up");
    check("irq_o Deasserted in IDLE", (irq_o === 1'b0), "irq_o is LOW");

    // ========================================================================
    // Scenario 3: START Condition & Slave Address ACK (Write Mode)
    // ========================================================================
    $display("\n--- SCENARIO 3: START Framing & Slave Address ACK ---");
    // Ensure t_BUF (130 cycles) bus-free time is satisfied before START
    wait_bus_free();

    // Enable controller
    ahb_write_reg(ADDR_CONTROL, 32'h00000001); // ENABLE=1

    // Issue START command
    ahb_write_reg(ADDR_COMMAND, CMD_START);

    // Verify BUSY asserts via AHB read
    ahb_read_reg(ADDR_STATUS, stat_val);
    check("STATUS.BUSY Asserted after START", (stat_val[STAT_BUSY_BIT] == 1'b1), "BUSY is 1");

    // Wait for START framing completion (DONE=1)
    wait_done_or_error(2000, stat_val, poll_timeout);
    check("START Completed without Timeout", (!poll_timeout && stat_val[STAT_DONE_BIT]), "DONE is 1");
    check("Slave Detected START", (slv_start_seen == 1'b1), "slv_start_seen is 1");

    // Transmit Slave Address 7'h50 with Write Bit (8'hA0)
    ahb_write_reg(ADDR_TX_DATA, 32'h000000A0);
    ahb_write_reg(ADDR_COMMAND, CMD_WRITE);

    // Wait for Address Phase completion
    wait_done_or_error(5000, stat_val, poll_timeout);
    check("Address Phase DONE", (!poll_timeout && stat_val[STAT_DONE_BIT]), "DONE is 1");
    check("Address ACKed (No ACK_ERROR)", (stat_val[STAT_ACK_ERROR_BIT] == 1'b0), "ACK_ERROR is 0");
    check("Slave Captured Matching Address", (slv_captured_addr == 7'h50 && slv_captured_rw == 1'b0),
          $sformatf("Addr=0x%02X, RW=%b", slv_captured_addr, slv_captured_rw));

    // ========================================================================
    // Scenario 4: Data Byte Write with Slave ACK & Multi-Byte Write
    // ========================================================================
    $display("\n--- SCENARIO 4: Data Byte Write with Slave ACK ---");
    // Write byte 0x3C
    ahb_write_reg(ADDR_TX_DATA, 32'h0000003C);
    ahb_write_reg(ADDR_COMMAND, CMD_WRITE);
    wait_done_or_error(5000, stat_val, poll_timeout);
    check("Data Byte 1 DONE", (!poll_timeout && stat_val[STAT_DONE_BIT]), "DONE is 1");
    check("Data Byte 1 ACKed", (stat_val[STAT_ACK_ERROR_BIT] == 1'b0), "No ACK error");
    check("Slave Received Byte 0x3C", (slv_captured_data == 8'h3C), $sformatf("Data=0x%02X", slv_captured_data));

    // Write second byte 0x7E in same transaction (multi-byte write)
    ahb_write_reg(ADDR_TX_DATA, 32'h0000007E);
    ahb_write_reg(ADDR_COMMAND, CMD_WRITE);
    wait_done_or_error(5000, stat_val, poll_timeout);
    check("Data Byte 2 DONE", (!poll_timeout && stat_val[STAT_DONE_BIT]), "DONE is 1");
    check("Data Byte 2 ACKed", (stat_val[STAT_ACK_ERROR_BIT] == 1'b0), "No ACK error");
    check("Slave Received Byte 0x7E", (slv_captured_data == 8'h7E), $sformatf("Data=0x%02X", slv_captured_data));

    // ========================================================================
    // Scenario 5: STOP Condition Generation
    // ========================================================================
    $display("\n--- SCENARIO 5: STOP Framing Verification ---");
    ahb_write_reg(ADDR_COMMAND, CMD_STOP);
    wait_done_or_error(3000, stat_val, poll_timeout);
    check("STOP Framing DONE", (!poll_timeout && stat_val[STAT_DONE_BIT]), "DONE is 1");

    // Verify Bus Idle post-STOP
    ahb_read_reg(ADDR_STATUS, stat_val);
    check("STATUS.BUSY Deasserted post-STOP", (stat_val[STAT_BUSY_BIT] == 1'b0), "BUSY is 0");
    check("Slave Detected STOP Condition", (slv_stop_seen == 1'b1), "slv_stop_seen is 1");
    check("SCL Floats HIGH post-STOP", (scl === 1'b1), "SCL line released");
    check("SDA Floats HIGH post-STOP", (sda === 1'b1), "SDA line released");

    // ========================================================================
    // Scenario 6: Slave Address NACK and Automatic Abort Recovery
    // ========================================================================
    $display("\n--- SCENARIO 6: Slave Address NACK & Automatic Abort ---");
    wait_bus_free(); // Ensure t_BUF qualification
    slv_force_addr_nack = 1'b1; // Force slave to NACK address

    // Issue START
    ahb_write_reg(ADDR_COMMAND, CMD_START);
    wait_done_or_error(2000, stat_val, poll_timeout);

    // Send address
    ahb_write_reg(ADDR_TX_DATA, 32'h000000A0);
    ahb_write_reg(ADDR_COMMAND, CMD_WRITE);

    // Wait for abort STOP completion
    wait_done_or_error(5000, stat_val, poll_timeout);
    check("NACK Error Detected", (stat_val[STAT_ACK_ERROR_BIT] == 1'b1), "STATUS.ACK_ERROR is 1");
    check("hw_done Suppressed on NACK", (stat_val[STAT_DONE_BIT] == 1'b0), "STATUS.DONE is 0");

    // Wait for automatic abort STOP sequence to release bus
    abort_wait = 0;
    do begin
      ahb_read_reg(ADDR_STATUS, stat_val);
      abort_wait++;
      @(posedge HCLK);
    end while (stat_val[STAT_BUSY_BIT] && abort_wait < 3000);

    check("Controller Aborted to IDLE", (stat_val[STAT_BUSY_BIT] == 1'b0), "BUSY returned to 0");
    check("Bus Lines Released post-NACK", (scl === 1'b1 && sda === 1'b1), "SCL and SDA float HIGH");
    slv_force_addr_nack = 1'b0; // Restore slave to normal ACK

    // ========================================================================
    // Scenario 7: Data Read with Master NACK & Read-on-Clear
    // ========================================================================
    $display("\n--- SCENARIO 7: Data Read with Master NACK & Read-on-Clear ---");
    wait_bus_free(); // Ensure t_BUF qualification
    slv_tx_data_byte = 8'hD5; // Slave prepares to return 0xD5

    // Issue START
    ahb_write_reg(ADDR_COMMAND, CMD_START);
    wait_done_or_error(2000, stat_val, poll_timeout);
    check("Read START Complete", (!poll_timeout && stat_val[STAT_DONE_BIT]), "DONE is 1");

    // Send Read Address (7'h50 + Read Bit 1 = 8'hA1)
    ahb_write_reg(ADDR_TX_DATA, 32'h000000A1);
    ahb_write_reg(ADDR_COMMAND, CMD_WRITE);
    wait_done_or_error(5000, stat_val, poll_timeout);
    check("Read Address Phase ACKed", (!stat_val[STAT_ACK_ERROR_BIT]), "No ACK error");

    // Issue READ Command & wait for byte + 9th clock cycle (Master NACK) to complete
    ahb_write_reg(ADDR_COMMAND, CMD_READ);
    wait_done_or_error(5000, stat_val, poll_timeout);
    check("Read Operation Completed (DONE)", (!poll_timeout && stat_val[STAT_DONE_BIT]), "DONE is 1");
    check("STATUS.RX_VALID Asserted", (stat_val[STAT_RX_VALID_BIT] == 1'b1), "RX_VALID is 1");

    // Read RX_DATA via AHB-Lite bus
    ahb_read_reg(ADDR_RX_DATA, rdata);
    check("Read Data Matches 0xD5", (rdata[7:0] == 8'hD5), $sformatf("RX_DATA = 0x%02X", rdata[7:0]));

    // Verify Read-on-Clear: STATUS.RX_VALID must now be 0
    ahb_read_reg(ADDR_STATUS, stat_val);
    check("STATUS.RX_VALID Cleared (Read-on-Clear)", (stat_val[STAT_RX_VALID_BIT] == 1'b0), "RX_VALID is 0");

    // Complete transaction with STOP (master is in ST_CMD_READY)
    ahb_write_reg(ADDR_COMMAND, CMD_STOP);
    wait_done_or_error(3000, stat_val, poll_timeout);
    check("Read Transaction STOP Complete", (stat_val[STAT_BUSY_BIT] == 1'b0), "BUSY is 0");

    // ========================================================================
    // Scenario 8: Repeated START Sequence (Write -> Restart -> Read)
    // ========================================================================
    $display("\n--- SCENARIO 8: Repeated START Sequence ---");
    wait_bus_free(); // Ensure t_BUF qualification
    // Phase 1: Write 0x44 to slave
    ahb_write_reg(ADDR_COMMAND, CMD_START);
    wait_done_or_error(2000, stat_val, poll_timeout);

    ahb_write_reg(ADDR_TX_DATA, 32'h000000A0);
    ahb_write_reg(ADDR_COMMAND, CMD_WRITE);
    wait_done_or_error(5000, stat_val, poll_timeout);

    ahb_write_reg(ADDR_TX_DATA, 32'h00000044);
    ahb_write_reg(ADDR_COMMAND, CMD_WRITE);
    wait_done_or_error(5000, stat_val, poll_timeout);
    check("Pre-Restart Write Completed", (slv_captured_data == 8'h44), "Slave received 0x44");

    // Phase 2: Issue Repeated START (without STOP)
    ahb_write_reg(ADDR_COMMAND, CMD_RESTART);
    wait_done_or_error(3000, stat_val, poll_timeout);
    check("Repeated START DONE", (!poll_timeout && stat_val[STAT_DONE_BIT]), "DONE is 1");

    ahb_read_reg(ADDR_STATUS, stat_val);
    check("STATUS.BUSY Continuously 1 During Restart", (stat_val[STAT_BUSY_BIT] == 1'b1), "BUSY remains 1");

    // Phase 3: Read 0x66 from slave after Repeated START
    slv_tx_data_byte = 8'h66;
    ahb_write_reg(ADDR_TX_DATA, 32'h000000A1); // Read address
    ahb_write_reg(ADDR_COMMAND, CMD_WRITE);
    wait_done_or_error(5000, stat_val, poll_timeout);

    ahb_write_reg(ADDR_COMMAND, CMD_READ);
    wait_done_or_error(5000, stat_val, poll_timeout);
    check("Post-Restart Read DONE", (!poll_timeout && stat_val[STAT_DONE_BIT]), "DONE is 1");
    check("Post-Restart RX_VALID Asserted", (stat_val[STAT_RX_VALID_BIT] == 1'b1), "RX_VALID is 1");

    ahb_read_reg(ADDR_RX_DATA, rdata);
    check("Post-Restart Read Data Matches 0x66", (rdata[7:0] == 8'h66), $sformatf("RX_DATA = 0x%02X", rdata[7:0]));

    // End with STOP
    ahb_write_reg(ADDR_COMMAND, CMD_STOP);
    wait_done_or_error(3000, stat_val, poll_timeout);
    check("Restart Transaction STOP Completed", (stat_val[STAT_BUSY_BIT] == 1'b0), "BUSY is 0");

    // ========================================================================
    // Scenario 9: Clock Stretching Tolerance
    // ========================================================================
    $display("\n--- SCENARIO 9: Hardware Clock-Stretching Tolerance ---");
    wait_bus_free(); // Ensure t_BUF qualification
    // Enable 3.0 us clock stretching during low phase of bit 3
    slv_stretch_en          = 1'b1;
    slv_stretch_duration_ns = 3000;
    slv_stretch_on_bit      = 4'd3;

    ahb_write_reg(ADDR_COMMAND, CMD_START);
    wait_done_or_error(2000, stat_val, poll_timeout);

    ahb_write_reg(ADDR_TX_DATA, 32'h000000A0);
    ahb_write_reg(ADDR_COMMAND, CMD_WRITE);
    wait_done_or_error(5000, stat_val, poll_timeout);

    // Write data byte 0x5A during which slave stretches SCL
    ahb_write_reg(ADDR_TX_DATA, 32'h0000005A);
    ahb_write_reg(ADDR_COMMAND, CMD_WRITE);

    // Wait for transfer with stretch: allow extra cycles for 3 us stretch
    wait_done_or_error(8000, stat_val, poll_timeout);
    check("Clock-Stretched Transfer Completed", (!poll_timeout && stat_val[STAT_DONE_BIT]), "DONE is 1");
    check("No Stretch Timeout Error", (stat_val[STAT_TIMEOUT_ERROR_BIT] == 1'b0), "TIMEOUT_ERROR is 0");
    check("Data 0x5A Captured Intact", (slv_captured_data == 8'h5A), $sformatf("Captured=0x%02X", slv_captured_data));

    ahb_write_reg(ADDR_COMMAND, CMD_STOP);
    wait_done_or_error(3000, stat_val, poll_timeout);
    slv_stretch_en = 1'b0; // Disable slave stretching

    // ========================================================================
    // Scenario 10: Hardware Clock-Stretching Timeout Detection
    // ========================================================================
    $display("\n--- SCENARIO 10: Hardware Clock-Stretching Timeout Detection ---");
    wait_bus_free(); // Ensure t_BUF qualification
    // Program short timeout limit of 300 cycles (3.0 us)
    ahb_write_reg(ADDR_TIMEOUT, 32'd300);

    // Slave stretches SCL for 500 us (exceeds 3.0 us limit) on data bit 2
    slv_stretch_en          = 1'b1;
    slv_stretch_duration_ns = 500000;
    slv_stretch_on_bit      = 4'd2;

    ahb_write_reg(ADDR_COMMAND, CMD_START);
    wait_done_or_error(2000, stat_val, poll_timeout);

    ahb_write_reg(ADDR_TX_DATA, 32'h000000A0);
    ahb_write_reg(ADDR_COMMAND, CMD_WRITE);
    wait_done_or_error(5000, stat_val, poll_timeout);

    // Write data byte during which slave stretches SCL on bit 2 indefinitely
    ahb_write_reg(ADDR_TX_DATA, 32'h000000EE);
    ahb_write_reg(ADDR_COMMAND, CMD_WRITE);

    // Wait for timeout abort event (limit 300 cycles << 5000 max_cycles)
    wait_done_or_error(5000, stat_val, poll_timeout);
    check("Timeout Error Detected", (stat_val[STAT_TIMEOUT_ERROR_BIT] == 1'b1), "STATUS.TIMEOUT_ERROR is 1");
    check("Timeout Forces BUSY to 0", (stat_val[STAT_BUSY_BIT] == 1'b0), "STATUS.BUSY is 0");
    check("Timeout Abort Suppressed DONE", (stat_val[STAT_DONE_BIT] == 1'b0), "STATUS.DONE is 0");

    slv_stretch_en = 1'b0; // Release slave stretch
    wait_bus_free(); // Allow lines to float HIGH and bus to qualify

    // ========================================================================
    // Scenario 11: System Interrupt Logic & W1C Clearing
    // ========================================================================
    $display("\n--- SCENARIO 11: System Interrupt Logic & W1C Clearing ---");
    wait_bus_free(); // Ensure t_BUF qualification
    // Enable Global Interrupt and individual Done/Error enables:
    // CONTROL[1] = 1 (INT_ENABLE)
    // IRQ[8] = DONE_IE, IRQ[9] = ACK_ERROR_IE, IRQ[10] = TIMEOUT_IE
    ahb_write_reg(ADDR_CONTROL, 32'h00000003); // ENABLE=1, INT_ENABLE=1
    ahb_write_reg(ADDR_IRQ, 32'h00000700);     // Enables [10:8] = 3'b111

    // Verify that TIMEOUT from Scenario 10 asserted irq_o once enabled
    check("irq_o Asserted on Prior Timeout", (irq_o === 1'b1), "irq_o is 1");
    ahb_read_reg(ADDR_IRQ, rdata);
    check("IRQ.TIMEOUT_PENDING Asserted", (rdata[2] == 1'b1), "TIMEOUT_PENDING is 1");

    // Clear all pending flags via W1C while preserving enables:
    ahb_write_reg(ADDR_IRQ, 32'h00000707); // W1C bits [2:0], keep enables [10:8]
    ahb_read_reg(ADDR_IRQ, rdata);
    check("All IRQ Pending Flags Cleared", (rdata[2:0] == 3'b000), "Pending flags are 0");
    check("irq_o Deasserted After W1C Clear", (irq_o === 1'b0), "irq_o is 0");

    // Execute START to generate a fresh DONE event
    ahb_write_reg(ADDR_COMMAND, CMD_START);
    wait_done_or_error(2000, stat_val, poll_timeout);

    // Verify interrupt fired upon DONE
    check("irq_o Asserted upon DONE", (irq_o === 1'b1), "irq_o is 1");
    ahb_read_reg(ADDR_IRQ, rdata);
    check("IRQ.DONE_PENDING Asserted", (rdata[0] == 1'b1), "DONE_PENDING is 1");

    // Clear DONE_PENDING via W1C while preserving enables
    ahb_write_reg(ADDR_IRQ, 32'h00000701); // W1C bit 0, keep enables
    ahb_read_reg(ADDR_IRQ, rdata);
    check("IRQ.DONE_PENDING Cleared", (rdata[0] == 1'b0), "DONE_PENDING is 0");
    check("irq_o Deasserted post-W1C", (irq_o === 1'b0), "irq_o is 0");

    // Close transaction with STOP
    ahb_write_reg(ADDR_COMMAND, CMD_STOP);
    wait_done_or_error(3000, stat_val, poll_timeout);
    // Clear STOP done interrupt
    ahb_write_reg(ADDR_IRQ, 32'h00000701);
    // Disable interrupts before Scenario 12
    ahb_write_reg(ADDR_CONTROL, 32'h00000001); // ENABLE=1, INT_ENABLE=0
    ahb_write_reg(ADDR_IRQ, 32'h00000007);     // Clear all pending flags, disable all

    // ========================================================================
    // Scenario 12: Recovery and New Transaction Post-Timeout
    // ========================================================================
    $display("\n--- SCENARIO 12: Recovery & New Transaction Post-Timeout ---");
    // Restore default timeout threshold: 100,000 cycles
    ahb_write_reg(ADDR_TIMEOUT, 32'd100000);

    // Ensure bus lines float HIGH (t_BUF elapsed)
    wait_bus_free();
    check("Bus Free post-recovery (SCL=1, SDA=1)", (scl === 1'b1 && sda === 1'b1), "Bus is free");

    // Execute complete transaction without any hardware reset:
    // START -> Addr 0x50 (Write) -> Data 0x99 -> STOP
    ahb_write_reg(ADDR_COMMAND, CMD_START);
    wait_done_or_error(2000, stat_val, poll_timeout);
    check("Post-Timeout START Successful", (!poll_timeout && stat_val[STAT_DONE_BIT]), "START DONE");

    ahb_write_reg(ADDR_TX_DATA, 32'h000000A0);
    ahb_write_reg(ADDR_COMMAND, CMD_WRITE);
    wait_done_or_error(5000, stat_val, poll_timeout);
    check("Post-Timeout Address ACKed", (stat_val[STAT_ACK_ERROR_BIT] == 1'b0), "Address ACKed");

    ahb_write_reg(ADDR_TX_DATA, 32'h00000099);
    ahb_write_reg(ADDR_COMMAND, CMD_WRITE);
    wait_done_or_error(5000, stat_val, poll_timeout);
    check("Post-Timeout Data Byte 0x99 ACKed", (slv_captured_data == 8'h99), "Slave received 0x99");

    ahb_write_reg(ADDR_COMMAND, CMD_STOP);
    wait_done_or_error(3000, stat_val, poll_timeout);
    check("Post-Timeout STOP Complete", (stat_val[STAT_BUSY_BIT] == 1'b0), "BUSY is 0");
    check("Final Bus State Floats HIGH", (scl === 1'b1 && sda === 1'b1), "Both lines High-Z");

    // ========================================================================
    // Final Test Summary
    // ========================================================================
    $display("\n============================================================================");
    $display("                      TASK E STEP 3 TEST SUMMARY                            ");
    $display("============================================================================");
    $display("  TOTAL VERIFICATION CHECKS : %0d", test_count);
    $display("  PASSED                    : %0d", pass_count);
    $display("  FAILED                    : %0d", fail_count);
    $display("============================================================================");

    if (fail_count == 0) begin
      $display("  >>> ALL TASK E FULL-CHIP VERIFICATION CHECKS PASSED SUCCESSFULLY! <<<");
    end else begin
      $display("  *** TESTBENCH FAILED WITH %0d FAILURES ***", fail_count);
    end
    $display("============================================================================\n");

    $finish;
  end

endmodule : tb_i2c_master_top
