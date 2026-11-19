// ============================================================================
// File:        ahb_tasks.svh
// Project:     AHB-Lite to I2C Master Controller
// Description: Reusable AHB-Lite bus transaction tasks for verification.
//              Accurately models standard AHB-Lite pipelined transactions,
//              wait-state injection, and back-to-back bursts.
// ============================================================================

`ifndef AHB_TASKS_SVH
`define AHB_TASKS_SVH

// ----------------------------------------------------------------------------
// Task: ahb_write
// Description: Standard zero-wait-state AHB-Lite single write transaction
// ----------------------------------------------------------------------------
task automatic ahb_write(
    input  logic [31:0] addr,
    input  logic [31:0] data,
    ref    logic        clk,
    ref    logic [31:0] haddr,
    ref    logic [31:0] hwdata,
    ref    logic        hwrite,
    ref    logic        hsel,
    ref    logic [1:0]  htrans,
    ref    logic        hready
);
  // Address Phase
  @(posedge clk);
  hsel   <= 1'b1;
  htrans <= 2'b10; // NONSEQ
  hwrite <= 1'b1;
  haddr  <= addr;
  hready <= 1'b1;

  // Data Phase
  @(posedge clk);
  hwdata <= data;
  // End of address burst / idle on bus
  hsel   <= 1'b0;
  htrans <= 2'b00; // IDLE
  hwrite <= 1'b0;
  haddr  <= 32'h0;

  @(posedge clk);
  hwdata <= 32'h0;
endtask

// ----------------------------------------------------------------------------
// Task: ahb_read
// Description: Standard zero-wait-state AHB-Lite single read transaction
// ----------------------------------------------------------------------------
task automatic ahb_read(
    input  logic [31:0] addr,
    output logic [31:0] data,
    ref    logic        clk,
    ref    logic [31:0] haddr,
    ref    logic [31:0] hrdata,
    ref    logic        hwrite,
    ref    logic        hsel,
    ref    logic [1:0]  htrans,
    ref    logic        hready
);
  // Address Phase
  @(posedge clk);
  hsel   <= 1'b1;
  htrans <= 2'b10; // NONSEQ
  hwrite <= 1'b0;
  haddr  <= addr;
  hready <= 1'b1;

  // Data Phase begins
  @(posedge clk);
  hsel   <= 1'b0;
  htrans <= 2'b00; // IDLE
  haddr  <= 32'h0;

  // Data Phase completes, sample HRDATA
  @(posedge clk);
  data   = hrdata;
endtask

// ----------------------------------------------------------------------------
// Task: ahb_write_wait
// Description: AHB-Lite write with wait states injected on HREADY during data phase
// ----------------------------------------------------------------------------
task automatic ahb_write_wait(
    input  logic [31:0] addr,
    input  logic [31:0] data,
    input  int          wait_cycles,
    ref    logic        clk,
    ref    logic [31:0] haddr,
    ref    logic [31:0] hwdata,
    ref    logic        hwrite,
    ref    logic        hsel,
    ref    logic [1:0]  htrans,
    ref    logic        hready
);
  // Address Phase
  @(posedge clk);
  hsel   <= 1'b1;
  htrans <= 2'b10;
  hwrite <= 1'b1;
  haddr  <= addr;
  hready <= 1'b1;

  // Enter Data Phase with Wait States
  @(posedge clk);
  hwdata <= data;
  hsel   <= 1'b0;
  htrans <= 2'b00;
  hwrite <= 1'b0;
  haddr  <= 32'h0;

  // Inject Wait States (HREADY = 0)
  repeat (wait_cycles) begin
    hready <= 1'b0;
    @(posedge clk);
  end

  // Complete Data Phase
  hready <= 1'b1;
  @(posedge clk);
  hwdata <= 32'h0;
endtask

// ----------------------------------------------------------------------------
// Task: ahb_read_wait
// Description: AHB-Lite read with wait states injected on HREADY during data phase
// ----------------------------------------------------------------------------
task automatic ahb_read_wait(
    input  logic [31:0] addr,
    output logic [31:0] data,
    input  int          wait_cycles,
    ref    logic        clk,
    ref    logic [31:0] haddr,
    ref    logic [31:0] hrdata,
    ref    logic        hwrite,
    ref    logic        hsel,
    ref    logic [1:0]  htrans,
    ref    logic        hready
);
  // Address Phase
  @(posedge clk);
  hsel   <= 1'b1;
  htrans <= 2'b10;
  hwrite <= 1'b0;
  haddr  <= addr;
  hready <= 1'b1;

  // Enter Data Phase with Wait States
  @(posedge clk);
  hsel   <= 1'b0;
  htrans <= 2'b00;
  haddr  <= 32'h0;

  // Inject Wait States (HREADY = 0)
  repeat (wait_cycles) begin
    hready <= 1'b0;
    @(posedge clk);
  end

  // Complete Data Phase
  hready <= 1'b1;
  @(posedge clk);
  data   = hrdata;
endtask

`endif // AHB_TASKS_SVH
