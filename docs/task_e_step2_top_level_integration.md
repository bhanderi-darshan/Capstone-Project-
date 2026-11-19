# Task E — Step 2: Top-Level RTL Architecture and Implementation Report

**Project:** Design and Verification of an AHB-Lite Based I²C Master Controller with Programmable Clock Generation and Hardware Clock-Stretching Timeout  
**Specification:** `Darshan_Project_doc.pdf`  
**Engineer:** Senior ASIC RTL Design Engineer  
**Date:** 18 November 2026  
**Status:** **STEP 2 IMPLEMENTATION & COMPILATION COMPLETE — READY FOR VERIFICATION**  

---

## 1. Executive Summary

In Step 2 of Task E, the synthesizable top-level module [`rtl/i2c_master_top.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/rtl/i2c_master_top.sv) was implemented and verified through clean IEEE 1800-2012 compilation using Icarus Verilog.

The top-level integrates exactly three peer modules:
1. `ahb_lite_slave_if u_ahb_slave`: Pipelined 32-bit AHB-Lite bus slave interface.
2. `i2c_registers u_registers`: Memory-mapped register bank, command strobes, status tracking, and W1C interrupt logic.
3. `i2c_master u_master`: I²C Master Controller FSM, open-drain multiplexing, 2-stage input synchronizers, which internally encapsulates `i2c_clock_gen u_clock_gen` and `i2c_timeout u_timeout`.

Zero existing RTL modules were modified. All 225 dynamic regression checks across Tasks A–D continue to pass with 100% success.

---

## 2. Top-Level Module Interface (`i2c_master_top`)

### 2.1 Port Declaration
```systemverilog
module i2c_master_top #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
)(
    // AHB-Lite System Clock and Reset
    input  logic                  HCLK,       // 100 MHz System Clock
    input  logic                  HRESETn,    // Active-Low System Reset

    // AHB-Lite Slave Bus Interface
    input  logic [ADDR_WIDTH-1:0] HADDR,      // Transfer address bus
    input  logic [DATA_WIDTH-1:0] HWDATA,     // Write data bus
    input  logic                  HWRITE,     // Transfer direction: 1 = Write, 0 = Read
    input  logic                  HSEL,       // Slave select
    input  logic [1:0]            HTRANS,     // Transfer type: 00=IDLE, 01=BUSY, 10=NONSEQ, 11=SEQ
    input  logic                  HREADY,     // Transfer ready from interconnect
    output logic [DATA_WIDTH-1:0] HRDATA,     // Read data bus
    output logic                  HREADYOUT,  // Slave ready output (zero wait-states)
    output logic                  HRESP,      // Transfer response: 0 = OKAY, 1 = ERROR

    // System Interrupt Line
    output logic                  irq_o,      // Active-HIGH interrupt request to CPU/NVIC

    // Physical I2C Bus Interface (Open-Drain Bidirectional Pins)
    inout  wire                   scl_io,     // Serial Clock Line (Open-Drain)
    inout  wire                   sda_io      // Serial Data Line  (Open-Drain)
);
```

### 2.2 Port Breakdown Table

| Port Name | Direction | Width | Domain | Description |
|---|:---:|:---:|:---:|---|
| `HCLK` | Input | 1 | Clock | AHB-Lite 100 MHz system clock |
| `HRESETn` | Input | 1 | Reset | Active-low asynchronous reset |
| `HADDR` | Input | 32 | `HCLK` | AHB-Lite transfer address |
| `HWDATA` | Input | 32 | `HCLK` | AHB-Lite write data bus |
| `HWRITE` | Input | 1 | `HCLK` | AHB-Lite transfer direction (1=Write, 0=Read) |
| `HSEL` | Input | 1 | `HCLK` | AHB slave selection strobe |
| `HTRANS` | Input | 2 | `HCLK` | AHB transfer type (NONSEQ, SEQ, IDLE, BUSY) |
| `HREADY` | Input | 1 | `HCLK` | System transfer ready / wait-state indicator |
| `HRDATA` | Output | 32 | `HCLK` | AHB-Lite read data bus |
| `HREADYOUT`| Output | 1 | `HCLK` | Slave ready output (always `1'b1` for 0-wait-state) |
| `HRESP` | Output | 1 | `HCLK` | Slave transfer response (`1'b0` = OKAY) |
| `irq_o` | Output | 1 | Comb | System interrupt line (active-HIGH) |
| `scl_io` | Inout | 1 | Asynch | Physical I²C SCL bidirectional open-drain pin |
| `sda_io` | Inout | 1 | Asynch | Physical I²C SDA bidirectional open-drain pin |

---

## 3. Structural Integration & Three Module Instances

```text
========================================================================================
                                    i2c_master_top
========================================================================================
    AHB-Lite Bus                                                     Physical I2C Bus
    ------------                                                     ----------------
  HCLK, HRESETn --------------------+-----------------------+            scl_io
  HADDR, HWDATA, HWRITE, etc.       |                       |            sda_io
        |                           v                       v               ^
        v                   +---------------+       +---------------+       |
+-------------------+       | i2c_registers |       |  i2c_master   |       |
| ahb_lite_slave_if |       |  u_registers  |       |   u_master    |       |
|    u_ahb_slave    |       +---------------+       +---------------+       |
+-------------------+               ^                       ^               |
        | reg_addr, reg_wdata, etc. | cmd_*, ctrl_*, etc.   |               |
        +---------------------------+-----------------------+               |
                                    | hw_busy, hw_done, etc.|               |
                                    +-----------------------+               |
                                                            | scl_drive_low |
                                                            | sda_drive_low |
                                                            +---------------+
                                                            | Open-Drain    |
                                                            | Drive: 0 / z  |
                                                            +---------------+
========================================================================================
```

### 3.1 Instance 1: AHB-Lite Slave Interface (`u_ahb_slave`)
Translates pipelined AHB address and data phases into synchronous internal register access strobes (`reg_write_en`, `reg_read_en`, `reg_addr[7:0]`, `reg_wdata[31:0]`) and multiplexes read data (`HRDATA <= reg_rdata`).
```systemverilog
  ahb_lite_slave_if #(
      .ADDR_WIDTH (ADDR_WIDTH),
      .DATA_WIDTH (DATA_WIDTH)
  ) u_ahb_slave (
      .HCLK        (HCLK),
      .HRESETn     (HRESETn),
      .HADDR       (HADDR),
      .HWDATA      (HWDATA),
      .HWRITE      (HWRITE),
      .HSEL        (HSEL),
      .HTRANS      (HTRANS),
      .HREADY      (HREADY),
      .HRDATA      (HRDATA),
      .HREADYOUT   (HREADYOUT),
      .HRESP       (HRESP),
      .reg_write_en(reg_write_en),
      .reg_read_en (reg_read_en),
      .reg_addr    (reg_addr),
      .reg_wdata   (reg_wdata),
      .reg_rdata   (reg_rdata)
  );
```

### 3.2 Instance 2: Memory-Mapped Register Bank (`u_registers`)
Decodes the 8 word-aligned 32-bit registers (0x00 to 0x1C), converts writes to `COMMAND` (0x14) into 1-cycle command strobes, latches hardware status, manages read-on-clear on `RX_DATA` (0x10), and evaluates W1C interrupt flags to drive `irq_o`.
```systemverilog
  i2c_registers #(
      .DATA_WIDTH (DATA_WIDTH)
  ) u_registers (
      .clk               (HCLK),
      .rst_n             (HRESETn),
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
      .cmd_start_o       (cmd_start),
      .cmd_write_o       (cmd_write),
      .cmd_read_o        (cmd_read),
      .cmd_stop_o        (cmd_stop),
      .cmd_restart_o     (cmd_restart),
      .ctrl_enable_o     (ctrl_enable),
      .ctrl_int_enable_o (), // Gated internally in i2c_registers to form irq_o
      .ctrl_auto_stop_o  (ctrl_auto_stop),
      .clk_high_count_o  (clk_high_count),
      .clk_low_count_o   (clk_low_count),
      .tx_data_o         (tx_data),
      .timeout_val_o     (timeout_limit),
      .irq_o             (irq_o)
  );
```

### 3.3 Instance 3: I²C Master Controller Core (`u_master`)
Implements the 12-state master protocol FSM. It internally instantiates `i2c_clock_gen u_clock_gen` and `i2c_timeout u_timeout`, synchronizes bus inputs through 2-stage flops (`scl_sync_q`, `sda_sync_q`), and outputs open-drain pull-down control strobes.
```systemverilog
  i2c_master u_master (
      .clk               (HCLK),
      .rst_n             (HRESETn),
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
      .scl_drive_low_o   (scl_drive_low),
      .sda_drive_low_o   (sda_drive_low)
  );
```

---

## 4. Internal Point-to-Point Connections

| Signal Name | Source | Destination | Width | Functional Role |
|---|---|---|:---:|---|
| `reg_write_en` | `u_ahb_slave` | `u_registers` | 1 | Register write strobe during AHB data phase |
| `reg_read_en` | `u_ahb_slave` | `u_registers` | 1 | Register read strobe during AHB data phase |
| `reg_addr[7:0]` | `u_ahb_slave` | `u_registers` | 8 | Word-aligned 8-bit register offset |
| `reg_wdata[31:0]` | `u_ahb_slave` | `u_registers` | 32 | Register write data from `HWDATA` |
| `reg_rdata[31:0]` | `u_registers` | `u_ahb_slave` | 32 | Register read data to `HRDATA` |
| `cmd_start` | `u_registers` | `u_master` | 1 | Initiate START framing strobe |
| `cmd_write` | `u_registers` | `u_master` | 1 | Initiate byte transmit strobe |
| `cmd_read` | `u_registers` | `u_master` | 1 | Initiate byte receive strobe |
| `cmd_stop` | `u_registers` | `u_master` | 1 | Initiate STOP framing strobe |
| `cmd_restart` | `u_registers` | `u_master` | 1 | Initiate Repeated START framing strobe |
| `ctrl_enable` | `u_registers` | `u_master` | 1 | Core enable bit (`CONTROL[0]`) |
| `ctrl_auto_stop` | `u_registers` | `u_master` | 1 | Automatic STOP bit (`CONTROL[2]`) |
| `clk_high_count[15:0]` | `u_registers` | `u_master` | 16 | High timing count (`CLOCK_DIV[15:0]`) |
| `clk_low_count[15:0]` | `u_registers` | `u_master` | 16 | Low timing count (`CLOCK_DIV[31:16]`) |
| `tx_data[7:0]` | `u_registers` | `u_master` | 8 | Transmit data / address byte (`TX_DATA[7:0]`) |
| `timeout_limit[31:0]` | `u_registers` | `u_master` | 32 | Timeout threshold (`TIMEOUT[31:0]`) |
| `hw_busy` | `u_master` | `u_registers` | 1 | Core active transaction flag (`STATUS[0]`) |
| `hw_tx_empty` | `u_master` | `u_registers` | 1 | TX holding buffer empty flag (`STATUS[1]`) |
| `hw_rx_valid` | `u_master` | `u_registers` | 1 | RX byte valid strobe (`STATUS[2]`) |
| `hw_ack_error` | `u_master` | `u_registers` | 1 | Slave NACK error pulse (`STATUS[3]`) |
| `hw_timeout_error`| `u_master` | `u_registers` | 1 | Clock stretch timeout pulse (`STATUS[4]`) |
| `hw_done` | `u_master` | `u_registers` | 1 | Operation complete pulse (`STATUS[5]`) |
| `hw_rx_data[7:0]` | `u_master` | `u_registers` | 8 | Received byte payload (`RX_DATA[7:0]`) |
| `scl_drive_low` | `u_master` | Open-Drain Pad | 1 | Pull SCL to GND when asserted |
| `sda_drive_low` | `u_master` | Open-Drain Pad | 1 | Pull SDA to GND when asserted |
| `scl_in` | Open-Drain Pad | `u_master` | 1 | SCL bus feedback into synchronizer |
| `sda_in` | Open-Drain Pad | `u_master` | 1 | SDA bus feedback into synchronizer |

---

## 5. Open-Drain Implementation & Pad Architectures

### 5.1 Synthesizable Top-Level Core Open-Drain Logic
The controller core guarantees strict open-drain behavior directly at the `scl_io` and `sda_io` bidirectional ports:
```systemverilog
  // When drive_low is 1'b1, actively pull line to GND (1'b0).
  // When drive_low is 1'b0, release line to High-Z (1'bz).
  // The line is NEVER driven actively to 1'b1.
  assign scl_io = scl_drive_low ? 1'b0 : 1'bz;
  assign sda_io = sda_drive_low ? 1'b0 : 1'bz;

  // Sample the physical bus lines back into the master synchronizers
  assign scl_in = scl_io;
  assign sda_in = sda_io;
```

### 5.2 FPGA Implementation Note (e.g. Xilinx / AMD Vivado)
In FPGA architectures, top-level `inout` pins infer hardware `IOBUF` primitives automatically:
```systemverilog
// Automatic vivado inference from inout wire:
IOBUF u_scl_iobuf (.O(scl_in), .IO(scl_io), .I(1'b0), .T(~scl_drive_low));
IOBUF u_sda_iobuf (.O(sda_in), .IO(sda_io), .I(1'b0), .T(~sda_drive_low));
```
Because the input `I` is tied to `1'b0` and tristate enable `T` is controlled by `~drive_low`, the pad is either actively pulling to GND or high-impedance.

### 5.3 ASIC Implementation Note (e.g. TSMC / GlobalFoundries Pad Cells)
In ASIC SoC integration, chip-boundary I/O pad cells (e.g. `PDUW0808CD`) are instantiated at the chip I/O ring:
```systemverilog
// ASIC pad wrapper connection:
PDUW0808CD u_pad_scl (.DOUT(scl_in), .PAD(SCL_PAD), .DIN(1'b0), .OEN(~scl_drive_low));
PDUW0808CD u_pad_sda (.DOUT(sda_in), .PAD(SDA_PAD), .DIN(1'b0), .OEN(~sda_drive_low));
```
The internal core code in `i2c_master_top.sv` maintains exact open-drain semantics without requiring proprietary library cells.

---

## 6. Compilation & Elaboration Results

The complete integrated RTL suite was compiled with the project toolchain:
```bash
iverilog -g2012 -Wall -o sim/i2c_master_top.vvp \
  rtl/i2c_pkg.sv \
  rtl/ahb_lite_slave_if.sv \
  rtl/i2c_registers.sv \
  rtl/i2c_clock_gen.sv \
  rtl/i2c_timeout.sv \
  rtl/i2c_master.sv \
  rtl/i2c_master_top.sv
```

### Elaboration Verification Checklist
- **All module instances elaborate:** **PASS** (Zero elaboration errors).
- **Missing or extra ports:** **NONE** (Exact port-for-port mapping).
- **Signal-width mismatches:** **NONE** (All 32-bit, 16-bit, 8-bit, and 1-bit ports aligned).
- **Multiple drivers:** **NONE** (Every net driven by exactly one driver).
- **Undriven top-level outputs:** **NONE** (`HRDATA`, `HREADYOUT`, `HRESP`, `irq_o`, `scl_io`, `sda_io` all actively driven).
- **Implicit nets:** **NONE** (All interconnects explicitly declared with SystemVerilog `logic` and `wire`).

---

## 7. Regression Invariance Verification

Existing regression testbenches were re-executed to confirm zero disruption to completed tasks:

| Regression Suite | Focus | Dynamic Checks | Status |
|---|---|:---:|:---:|
| **Task A** | [`tb/tb_ahb_registers.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/tb/tb_ahb_registers.sv) | 46 / 46 | **100% PASS** |
| **Task B** | [`tb/tb_i2c_clock_gen.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/tb/tb_i2c_clock_gen.sv) | 49 / 49 | **100% PASS** |
| **Task D Unit** | [`tb/tb_i2c_timeout.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/tb/tb_i2c_timeout.sv) | 37 / 37 | **100% PASS** |
| **Task C & D Integration** | [`tb/tb_i2c_master.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/tb/tb_i2c_master.sv) | 93 / 93 | **100% PASS** |
| **TOTAL** | All Regression Suites | **225 / 225** | **100% PASS (0 Failures)** |

---

## 8. Unresolved Issues

- **Critical Issues:** **NONE**.
- **Major Issues:** **NONE**.
- **Minor Issues:** **NONE**.
- **Freeze Status:** Confirmed. All pre-existing RTL files in `rtl/` remain untouched.
- **Next Step:** Proceed to Task E Step 3 (Comprehensive Top-Level Testbench and Full-Chip System Verification).
