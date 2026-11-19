# Task E — Step 1: RTL Interface Inspection Report

**Project:** Design and Verification of an AHB-Lite Based I²C Master Controller with Programmable Clock Generation and Hardware Clock-Stretching Timeout  
**Primary Specification:** `Darshan_Project_doc.pdf`  
**Engineer:** Senior ASIC RTL Design and Verification Engineer  
**Date:** 18 November 2026  
**Status:** **STEP 1 COMPLETE — AWAITING ARCHITECTURAL APPROVAL BEFORE STEP 2**  

---

## 1. Project Directory Structure

```text
17-11-2026/
├── Darshan_Project_doc.pdf          # Primary academic and design specification
├── darshan_deciphered.txt           # Extracted project specification transcript
├── docs/
│   ├── task_b_design_notes.md       # Task B clock generator architecture notes
│   ├── task_c_design_notes.md       # Task C master controller FSM design notes
│   ├── task_d_timeout_design_notes.md# Task D hardware stretch timeout architecture
│   ├── task_d_final_audit.md        # Comprehensive 7-dimension formal audit
│   ├── task_d_final_closure.md      # Final verification closure & freeze evidence
│   ├── task_d_report_correction_summary.md # Reconciliation documentation
│   └── task_e_step1_rtl_interface_inspection.md # THIS REPORT
├── rtl/
│   ├── i2c_pkg.sv                   # Package: register map, bitfields, FSM states
│   ├── ahb_lite_slave_if.sv         # Task A: AHB-Lite 32-bit protocol adapter
│   ├── i2c_registers.sv             # Task A: Memory-mapped register bank & IRQ
│   ├── i2c_clock_gen.sv             # Task B: Programmable SCL clock generator
│   ├── i2c_timeout.sv               # Task D: Hardware clock-stretching timeout unit
│   └── i2c_master.sv                # Task C/D: I2C Master FSM & line multiplexing
├── tb/
│   ├── ahb_tasks.svh                # AHB bus master BFMs & transaction tasks
│   ├── i2c_slave_model.sv           # Emulated I2C slave with stretching & NACK
│   ├── tb_ahb_registers.sv          # Task A testbench (46 dynamic checks)
│   ├── tb_i2c_clock_gen.sv          # Task B testbench (49 dynamic checks)
│   ├── tb_i2c_timeout.sv            # Task D unit testbench (37 dynamic checks)
│   └── tb_i2c_master.sv             # Task C/D integration testbench (93 dynamic checks)
├── sim/
│   ├── filelist.f                   # Compilation filelist
│   ├── run_phase1.bat / .sh         # Phase 1 simulation scripts
│   ├── task_a_simulation.log        # 46 / 46 PASS log
│   ├── task_b_simulation.log        # 49 / 49 PASS log
│   ├── task_d_timeout_unit_simulation.log # 37 / 37 PASS log
│   └── task_d_simulation.log        # 93 / 93 PASS log
└── tools/
    └── iverilog/                    # Embedded IEEE 1800-2012 Icarus Verilog toolchain
```

---

## 2. Module-by-Module Interface Analysis

### 2.1 Package: `i2c_pkg.sv`
- **File:** [`rtl/i2c_pkg.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/rtl/i2c_pkg.sv)
- **Role:** Shared SystemVerilog package containing address definitions, register bitfields, default timing constants, and the 12-state FSM enumerated type `i2c_state_t`.
- **Address Map:**
  - `ADDR_CONTROL   = 8'h00` (Bits: 0: `ENABLE`, 1: `INT_ENABLE`, 2: `AUTO_STOP`)
  - `ADDR_STATUS    = 8'h04` (Bits: 0: `BUSY`, 1: `TX_EMPTY`, 2: `RX_VALID`, 3: `ACK_ERROR`, 4: `TIMEOUT_ERROR`, 5: `DONE`)
  - `ADDR_CLOCK_DIV = 8'h08` (Bits [15:0]: `HIGH_COUNT`, Bits [31:16]: `LOW_COUNT`)
  - `ADDR_TX_DATA   = 8'h0C` (Bits [7:0]: Transmit Data / 7-bit Address + R/W#)
  - `ADDR_RX_DATA   = 8'h10` (Bits [7:0]: Received Data Byte, Read-on-Clear)
  - `ADDR_COMMAND   = 8'h14` (Write-only Strobes: 0: `START`, 1: `WRITE`, 2: `READ`, 3: `STOP`, 4: `RESTART`)
  - `ADDR_TIMEOUT   = 8'h18` (Bits [31:0]: Stretch timeout threshold in HCLK cycles; 0 disables)
  - `ADDR_IRQ       = 8'h1C` (Status [2:0]: `DONE`, `ACK_ERROR`, `TIMEOUT` (W1C); Enables [10:8]: `DONE_IE`, `ACK_IE`, `TIMEOUT_IE`)

---

### 2.2 Module: `ahb_lite_slave_if`
- **File:** [`rtl/ahb_lite_slave_if.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/rtl/ahb_lite_slave_if.sv)
- **Parameters:**
  - `ADDR_WIDTH`: Integer, default `32`
  - `DATA_WIDTH`: Integer, default `32`
- **Ports:**

| Port Name | Direction | Width | Domain | Description |
|---|:---:|:---:|:---:|---|
| `HCLK` | Input | 1 | Clock | AHB System Clock (100 MHz) |
| `HRESETn` | Input | 1 | Reset | Active-Low Asynchronous Reset |
| `HADDR` | Input | `ADDR_WIDTH` (32) | `HCLK` | AHB-Lite Transfer Address Bus |
| `HWDATA` | Input | `DATA_WIDTH` (32) | `HCLK` | AHB-Lite Write Data Bus |
| `HWRITE` | Input | 1 | `HCLK` | AHB-Lite Transfer Direction (1 = Write, 0 = Read) |
| `HSEL` | Input | 1 | `HCLK` | AHB Slave Select Strobe |
| `HTRANS` | Input | 2 | `HCLK` | AHB Transfer Type (00=IDLE, 01=BUSY, 10=NONSEQ, 11=SEQ) |
| `HREADY` | Input | 1 | `HCLK` | System Bus Transfer Ready / Wait Strobe |
| `HRDATA` | Output | `DATA_WIDTH` (32) | `HCLK` | AHB-Lite Read Data Bus |
| `HREADYOUT`| Output | 1 | `HCLK` | Slave Ready Output (always `1'b1` for 0-wait-state) |
| `HRESP` | Output | 1 | `HCLK` | Slave Response (`1'b0` = `RESP_OKAY`) |
| `reg_write_en`| Output | 1 | `HCLK` | 1-cycle Active Write Strobe to Register Bank |
| `reg_read_en` | Output | 1 | `HCLK` | 1-cycle Active Read Completion Strobe to Register Bank |
| `reg_addr` | Output | 8 | `HCLK` | Word-aligned 8-bit Register Address (`{HADDR[7:2], 2'b00}`) |
| `reg_wdata`| Output | `DATA_WIDTH` (32) | `HCLK` | Forwarded Register Write Data Bus |
| `reg_rdata`| Input | `DATA_WIDTH` (32) | `HCLK` | Register Read Data from `i2c_registers` |

- **Protocol Behavior:**
  - Implements 2-phase AHB-Lite pipelining (Address Phase sampled when `HSEL && HREADY && HTRANS[1] == 1'b1`, Data Phase executed on subsequent cycle).
  - Pipelined control registers: `valid_data_phase_q`, `write_q`, `addr_q[7:0]`.
  - Zero-wait-state slave operation: `HREADYOUT = 1'b1`, `HRESP = 1'b0`.

---

### 2.3 Module: `i2c_registers`
- **File:** [`rtl/i2c_registers.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/rtl/i2c_registers.sv)
- **Parameters:**
  - `DATA_WIDTH`: Integer, default `32`
- **Ports:**

| Port Name | Direction | Width | Domain | Description |
|---|:---:|:---:|:---:|---|
| `clk` | Input | 1 | Clock | System Clock (100 MHz, connects to `HCLK`) |
| `rst_n` | Input | 1 | Reset | Active-Low Reset (connects to `HRESETn`) |
| `reg_write_en` | Input | 1 | `clk` | Write enable strobe from `ahb_lite_slave_if` |
| `reg_read_en` | Input | 1 | `clk` | Read enable strobe from `ahb_lite_slave_if` |
| `reg_addr` | Input | 8 | `clk` | Register address from `ahb_lite_slave_if` |
| `reg_wdata` | Input | `DATA_WIDTH` (32) | `clk` | Write data from `ahb_lite_slave_if` |
| `reg_rdata` | Output | `DATA_WIDTH` (32) | Comb | Read data back to `ahb_lite_slave_if` |
| `hw_busy_i` | Input | 1 | `clk` | Core active transaction flag (from `i2c_master`) |
| `hw_tx_empty_i`| Input | 1 | `clk` | TX holding buffer empty flag (from `i2c_master`) |
| `hw_rx_valid_i`| Input | 1 | `clk` | RX data byte valid strobe (from `i2c_master`) |
| `hw_ack_error_i`| Input | 1 | `clk` | Slave NACK error pulse (from `i2c_master`) |
| `hw_timeout_error_i`| Input | 1 | `clk`| Clock stretch timeout error pulse (from `i2c_master`) |
| `hw_done_i` | Input | 1 | `clk` | Phase/command completion pulse (from `i2c_master`) |
| `hw_rx_data_i` | Input | 8 | `clk` | Received byte payload (from `i2c_master`) |
| `cmd_start_o` | Output | 1 | `clk` | Issue START condition strobe |
| `cmd_write_o` | Output | 1 | `clk` | Issue Byte Write strobe |
| `cmd_read_o` | Output | 1 | `clk` | Issue Byte Read strobe |
| `cmd_stop_o` | Output | 1 | `clk` | Issue STOP condition strobe |
| `cmd_restart_o`| Output | 1 | `clk` | Issue Repeated START strobe |
| `ctrl_enable_o`| Output | 1 | `clk` | Controller Core Enable (`CONTROL[0]`) |
| `ctrl_int_enable_o`| Output | 1 | `clk`| Global Interrupt Enable (`CONTROL[1]`) |
| `ctrl_auto_stop_o`| Output | 1 | `clk` | Auto STOP enable (`CONTROL[2]`) |
| `clk_high_count_o`| Output | 16 | `clk`| SCL HIGH timing count (`CLOCK_DIV[15:0]`) |
| `clk_low_count_o` | Output | 16 | `clk`| SCL LOW timing count (`CLOCK_DIV[31:16]`) |
| `tx_data_o` | Output | 8 | `clk` | Transmit Data / Address Byte (`TX_DATA[7:0]`) |
| `timeout_val_o` | Output | 32 | `clk`| Stretch Timeout threshold (`TIMEOUT[31:0]`) |
| `irq_o` | Output | 1 | Comb | System Interrupt Line |

- **Internal Capabilities:**
  - Auto-clearing command strobes (1-cycle pulse upon write to `ADDR_COMMAND`).
  - Read-on-clear logic on `ADDR_RX_DATA` for `stat_rx_valid_q`.
  - W1C logic with hardware precedence for pending interrupt flags.
  - Sticky status indicators reset on any new non-zero command strobe.

---

### 2.4 Module: `i2c_clock_gen`
- **File:** [`rtl/i2c_clock_gen.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/rtl/i2c_clock_gen.sv)
- **Parameters:** None
- **Ports:**

| Port Name | Direction | Width | Domain | Description |
|---|:---:|:---:|:---:|---|
| `clk` | Input | 1 | Clock | System Clock (100 MHz) |
| `reset_n` | Input | 1 | Reset | Active-Low Reset |
| `start_cycle` | Input | 1 | `clk` | Request generation of 1 SCL clock cycle |
| `high_count` | Input | 16 | `clk` | Programmed SCL HIGH duration in HCLK cycles |
| `low_count` | Input | 16 | `clk` | Programmed SCL LOW duration in HCLK cycles |
| `scl_in` | Input | 1 | `clk` | Synchronized physical SCL bus input |
| `abort` | Input | 1 | `clk` | Synchronous abort strobe (resets to `STATE_IDLE`) |
| `scl_drive_low`| Output | 1 | `clk` | 1 = Pull SCL LOW, 0 = Release SCL (Open-Drain) |
| `busy` | Output | 1 | `clk` | 1 = Clock generator active generating cycle |
| `cycle_done` | Output | 1 | `clk` | 1-cycle completion pulse at end of cycle |
| `stretch_wait` | Output | 1 | `clk` | 1 = Waiting in `STATE_WAIT_SCL_HIGH` for slave release |

- **Integration Relationship:**
  - Already instantiated internally inside `rtl/i2c_master.sv` as instance `u_clock_gen`.

---

### 2.5 Module: `i2c_timeout`
- **File:** [`rtl/i2c_timeout.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/rtl/i2c_timeout.sv)
- **Parameters:** None
- **Ports:**

| Port Name | Direction | Width | Domain | Description |
|---|:---:|:---:|:---:|---|
| `clk` | Input | 1 | Clock | System Clock (100 MHz) |
| `reset_n` | Input | 1 | Reset | Active-Low Reset |
| `scl_released` | Input | 1 | `clk` | 1 = Master released SCL (`~scl_drive_low_o & active`) |
| `scl_in` | Input | 1 | `clk` | Synchronized physical SCL bus input |
| `timeout_limit`| Input | 32 | `clk` | Programmed threshold in HCLK cycles (0 = disabled) |
| `timeout_event`| Output | 1 | `clk` | 1-cycle active-HIGH pulse on exact $N$-th cycle |
| `stretch_active`| Output | 1 | Comb | 1 = `scl_released && !scl_in` |

- **Integration Relationship:**
  - Already instantiated internally inside `rtl/i2c_master.sv` as instance `u_timeout`.

---

### 2.6 Module: `i2c_master`
- **File:** [`rtl/i2c_master.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/rtl/i2c_master.sv)
- **Parameters:** None
- **Ports:**

| Port Name | Direction | Width | Domain | Description |
|---|:---:|:---:|:---:|---|
| `clk` | Input | 1 | Clock | System Clock (100 MHz) |
| `rst_n` | Input | 1 | Reset | Active-Low Reset |
| `cmd_start_i` | Input | 1 | `clk` | Command strobe: START |
| `cmd_write_i` | Input | 1 | `clk` | Command strobe: Write Byte |
| `cmd_read_i` | Input | 1 | `clk` | Command strobe: Read Byte |
| `cmd_stop_i` | Input | 1 | `clk` | Command strobe: STOP |
| `cmd_restart_i`| Input | 1 | `clk` | Command strobe: Repeated START |
| `ctrl_enable_i`| Input | 1 | `clk` | Core Enable (`CONTROL[0]`) |
| `ctrl_auto_stop_i`| Input | 1 | `clk` | AUTO_STOP enable (`CONTROL[2]`) |
| `clk_high_count_i`| Input | 16 | `clk`| SCL HIGH count (`CLOCK_DIV[15:0]`) |
| `clk_low_count_i` | Input | 16 | `clk`| SCL LOW count (`CLOCK_DIV[31:16]`) |
| `timeout_limit_i` | Input | 32 | `clk`| Stretch timeout limit (`TIMEOUT[31:0]`) |
| `tx_data_i` | Input | 8 | `clk` | Transmit Data / Address Byte (`TX_DATA[7:0]`) |
| `hw_busy_o` | Output | 1 | `clk` | 1 = Transaction in progress (`STATUS[0]`) |
| `hw_tx_empty_o`| Output | 1 | `clk` | 1 = TX holding buffer empty (`STATUS[1]`) |
| `hw_rx_valid_o`| Output | 1 | `clk` | 1-cycle pulse: RX byte available (`STATUS[2]`) |
| `hw_ack_error_o`| Output | 1 | `clk` | 1-cycle pulse: NACK detected (`STATUS[3]`) |
| `hw_timeout_error_o`| Output | 1 | `clk`| 1-cycle pulse: Timeout fired (`STATUS[4]`) |
| `hw_done_o` | Output | 1 | `clk` | 1-cycle pulse: Phase complete (`STATUS[5]`) |
| `hw_rx_data_o` | Output | 8 | `clk` | Received byte payload (`RX_DATA[7:0]`) |
| `scl_in` | Input | 1 | Asynch | Raw physical SCL bus input (synchronized internally) |
| `sda_in` | Input | 1 | Asynch | Raw physical SDA bus input (synchronized internally) |
| `scl_drive_low_o`| Output | 1 | `clk` | 1 = Pull SCL LOW, 0 = High-Z Float |
| `sda_drive_low_o`| Output | 1 | `clk` | 1 = Pull SDA LOW, 0 = High-Z Float |

- **Internal Sub-Instances:**
  - Instantiates `i2c_timeout u_timeout` ([`rtl/i2c_master.sv:95`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/rtl/i2c_master.sv#L95)).
  - Instantiates `i2c_clock_gen u_clock_gen` ([`rtl/i2c_master.sv:156`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/rtl/i2c_master.sv#L156)).
  - Contains 2-stage input synchronizers (`scl_sync_q`, `sda_sync_q`).
  - Contains glitch-free SCL handover overlap logic (`handover_overlap_q`).
  - Contains bus-busy qualification counter (`bus_free_cnt_q`).

---

## 3. Structural Integration Hierarchy

An essential design finding of this inspection is that the six RTL files naturally form a clean **3-tier hierarchical IP architecture**:

```text
TOP LEVEL (i2c_master_top)
├── u_ahb_slave : ahb_lite_slave_if (Pipelined AHB-Lite bus interface)
├── u_registers : i2c_registers     (Memory-mapped register bank & IRQ logic)
└── u_master    : i2c_master        (I2C Master Controller FSM & line drivers)
      ├── u_clock_gen : i2c_clock_gen (Task B SCL clock generator)
      └── u_timeout   : i2c_timeout   (Task D hardware clock stretch timeout)
```

Because `i2c_clock_gen` and `i2c_timeout` are already instantiated and verified inside `i2c_master.sv`, the top-level integration module needs to instantiate exactly **three peer sub-modules**:
1. `ahb_lite_slave_if` (`u_ahb_slave`)
2. `i2c_registers` (`u_registers`)
3. `i2c_master` (`u_master`)

This preserves 100% of the verified Task B, Task C, and Task D RTL code without requiring any RTL modifications or duplicating sub-blocks.

---

## 4. Complete Integration Connection Table

The table below enumerates every point-to-point connection required in the proposed top-level module:

| # | Source Module | Source Signal | Destination Module | Destination Signal | Width | Verified in RTL |
|:---:|---|---|---|---|:---:|:---:|
| 1 | Top Pin | `HCLK` | `u_ahb_slave` | `HCLK` | 1 | YES |
| 2 | Top Pin | `HCLK` | `u_registers` | `clk` | 1 | YES |
| 3 | Top Pin | `HCLK` | `u_master` | `clk` | 1 | YES |
| 4 | Top Pin | `HRESETn` | `u_ahb_slave` | `HRESETn` | 1 | YES |
| 5 | Top Pin | `HRESETn` | `u_registers` | `rst_n` | 1 | YES |
| 6 | Top Pin | `HRESETn` | `u_master` | `rst_n` | 1 | YES |
| 7 | Top Pin | `HADDR` | `u_ahb_slave` | `HADDR` | 32 | YES |
| 8 | Top Pin | `HWDATA` | `u_ahb_slave` | `HWDATA` | 32 | YES |
| 9 | Top Pin | `HWRITE` | `u_ahb_slave` | `HWRITE` | 1 | YES |
| 10 | Top Pin | `HSEL` | `u_ahb_slave` | `HSEL` | 1 | YES |
| 11 | Top Pin | `HTRANS` | `u_ahb_slave` | `HTRANS` | 2 | YES |
| 12 | Top Pin | `HREADY` | `u_ahb_slave` | `HREADY` | 1 | YES |
| 13 | `u_ahb_slave` | `HRDATA` | Top Pin | `HRDATA` | 32 | YES |
| 14 | `u_ahb_slave` | `HREADYOUT` | Top Pin | `HREADYOUT` | 1 | YES |
| 15 | `u_ahb_slave` | `HRESP` | Top Pin | `HRESP` | 1 | YES |
| 16 | `u_ahb_slave` | `reg_write_en` | `u_registers` | `reg_write_en` | 1 | YES |
| 17 | `u_ahb_slave` | `reg_read_en` | `u_registers` | `reg_read_en` | 1 | YES |
| 18 | `u_ahb_slave` | `reg_addr` | `u_registers` | `reg_addr` | 8 | YES |
| 19 | `u_ahb_slave` | `reg_wdata` | `u_registers` | `reg_wdata` | 32 | YES |
| 20 | `u_registers` | `reg_rdata` | `u_ahb_slave` | `reg_rdata` | 32 | YES |
| 21 | `u_registers` | `cmd_start_o` | `u_master` | `cmd_start_i` | 1 | YES |
| 22 | `u_registers` | `cmd_write_o` | `u_master` | `cmd_write_i` | 1 | YES |
| 23 | `u_registers` | `cmd_read_o` | `u_master` | `cmd_read_i` | 1 | YES |
| 24 | `u_registers` | `cmd_stop_o` | `u_master` | `cmd_stop_i` | 1 | YES |
| 25 | `u_registers` | `cmd_restart_o` | `u_master` | `cmd_restart_i` | 1 | YES |
| 26 | `u_registers` | `ctrl_enable_o` | `u_master` | `ctrl_enable_i` | 1 | YES |
| 27 | `u_registers` | `ctrl_auto_stop_o`| `u_master` | `ctrl_auto_stop_i` | 1 | YES |
| 28 | `u_registers` | `clk_high_count_o`| `u_master` | `clk_high_count_i` | 16 | YES |
| 29 | `u_registers` | `clk_low_count_o` | `u_master` | `clk_low_count_i` | 16 | YES |
| 30 | `u_registers` | `tx_data_o` | `u_master` | `tx_data_i` | 8 | YES |
| 31 | `u_registers` | `timeout_val_o` | `u_master` | `timeout_limit_i` | 32 | YES |
| 32 | `u_master` | `hw_busy_o` | `u_registers` | `hw_busy_i` | 1 | YES |
| 33 | `u_master` | `hw_tx_empty_o` | `u_registers` | `hw_tx_empty_i` | 1 | YES |
| 34 | `u_master` | `hw_rx_valid_o` | `u_registers` | `hw_rx_valid_i` | 1 | YES |
| 35 | `u_master` | `hw_ack_error_o` | `u_registers` | `hw_ack_error_i` | 1 | YES |
| 36 | `u_master` | `hw_timeout_error_o`| `u_registers` | `hw_timeout_error_i`| 1 | YES |
| 37 | `u_master` | `hw_done_o` | `u_registers` | `hw_done_i` | 1 | YES |
| 38 | `u_master` | `hw_rx_data_o` | `u_registers` | `hw_rx_data_i` | 8 | YES |
| 39 | `u_registers` | `irq_o` | Top Pin | `irq_o` (or `IRQ`) | 1 | YES |
| 40 | Top Pin | `scl_in` | `u_master` | `scl_in` | 1 | YES |
| 41 | Top Pin | `sda_in` | `u_master` | `sda_in` | 1 | YES |
| 42 | `u_master` | `scl_drive_low_o`| Top Pin | `scl_drive_low_o` (or `scl_oe`) | 1 | YES |
| 43 | `u_master` | `sda_drive_low_o`| Top Pin | `sda_drive_low_o` (or `sda_oe`) | 1 | YES |

---

## 5. Proposed Top-Level Block Architecture

### 5.1 Top-Level Module Naming Recommendation
Based on project naming standards in `Darshan_Project_doc.pdf` and typical SoC design conventions:
- **Recommended Module Name:** `i2c_master_top`
- **Alternative Alias:** `ahb_i2c_top`
- **Recommendation:** Use `i2c_master_top` (matching `i2c_master.sv` and `i2c_registers.sv`), located in `rtl/i2c_master_top.sv`.

### 5.2 Physical I²C Pin & Open-Drain Architecture
In accordance with ASIC synthesis and FPGA design best practices:
1. **ASIC/FPGA Core Port Style (Standard IP Core Interface):**
   ```systemverilog
   // Physical I2C Bus Interface
   input  logic scl_in,           // Physical SCL input from IO pad
   input  logic sda_in,           // Physical SDA input from IO pad
   output logic scl_drive_low_o,  // 1 = Assert pull-down pad to GND, 0 = High-Z (release)
   output logic sda_drive_low_o,  // 1 = Assert pull-down pad to GND, 0 = High-Z (release)
   ```
2. **Tri-State / Inout Emulation for Simulation Testbenches:**
   In simulation testbenches or FPGA top-level wrappers with bidirectional `inout` pins:
   ```systemverilog
   assign scl_io = scl_drive_low_o ? 1'b0 : 1'bz;
   assign sda_io = sda_drive_low_o ? 1'b0 : 1'bz;
   assign scl_in = scl_io;
   assign sda_in = sda_io;
   ```
   *Strict Open-Drain Guarantee:* Neither line is ever driven actively to `1'b1`. When the master releases the line (`drive_low == 0`), the output enters high-impedance (`1'bz`), allowing external pull-up resistors to float the bus to $V_{DD}$.

### 5.3 Complete Proposed Top-Level Port List (`i2c_master_top`)
```systemverilog
module i2c_master_top #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
)(
    // AHB-Lite System Clock & Reset
    input  logic                  HCLK,
    input  logic                  HRESETn,

    // AHB-Lite Slave Bus Interface
    input  logic [ADDR_WIDTH-1:0] HADDR,
    input  logic [DATA_WIDTH-1:0] HWDATA,
    input  logic                  HWRITE,
    input  logic                  HSEL,
    input  logic [1:0]            HTRANS,
    input  logic                  HREADY,
    output logic [DATA_WIDTH-1:0] HRDATA,
    output logic                  HREADYOUT,
    output logic                  HRESP,

    // System Interrupt
    output logic                  irq_o,

    // Physical I2C Bus Interface (Open-Drain Driver Enables & Inputs)
    input  logic                  scl_in,
    input  logic                  sda_in,
    output logic                  scl_drive_low_o,
    output logic                  sda_drive_low_o
);
```

---

## 6. Signal-Width and Type Verification

| Signal Path | Source Width | Dest Width | Type | Status |
|---|:---:|:---:|---|:---:|
| `reg_addr` | 8 bits | 8 bits | `logic [7:0]` | **MATCH** |
| `reg_wdata` | 32 bits | 32 bits | `logic [31:0]` | **MATCH** |
| `reg_rdata` | 32 bits | 32 bits | `logic [31:0]` | **MATCH** |
| `clk_high_count` | 16 bits | 16 bits | `logic [15:0]` | **MATCH** |
| `clk_low_count` | 16 bits | 16 bits | `logic [15:0]` | **MATCH** |
| `tx_data` | 8 bits | 8 bits | `logic [7:0]` | **MATCH** |
| `hw_rx_data` | 8 bits | 8 bits | `logic [7:0]` | **MATCH** |
| `timeout_limit` | 32 bits | 32 bits | `logic [31:0]` | **MATCH** |
| Command Strobes (`start`, `write`, `read`, `stop`, `restart`) | 1 bit each | 1 bit each | `logic` | **MATCH** |
| Hardware Status Flags (`busy`, `tx_empty`, `rx_valid`, `ack_error`, `timeout_error`, `done`) | 1 bit each | 1 bit each | `logic` | **MATCH** |
| Open-drain line drives (`scl_drive_low`, `sda_drive_low`) | 1 bit each | 1 bit each | `logic` | **MATCH** |

---

## 7. Clock and Reset Domain Analysis

1. **Clock Domain:**
   - Single synchronous clock domain: `HCLK` (100 MHz, 10 ns period).
   - `HCLK` directly drives `ahb_lite_slave_if`, `i2c_registers`, `i2c_master`, `i2c_clock_gen`, and `i2c_timeout`.
   - **Clock Domain Crossings (CDC):** **Zero**.
2. **Reset Polarity & Deassertion:**
   - All modules use an active-low asynchronous assert, synchronous deassert reset structure.
   - Signal names:
     - `ahb_lite_slave_if`: `HRESETn`
     - `i2c_registers`: `rst_n`
     - `i2c_master`: `rst_n`
     - `i2c_clock_gen`: `reset_n` (inside `i2c_master`)
     - `i2c_timeout`: `reset_n` (inside `i2c_master`)
   - Reset wiring: `HRESETn` ties directly to all child reset ports.
   - Synchronizers reset value: `2'b11`, matching the passive HIGH pull-up state of the I²C bus.

---

## 8. Integration Risk Analysis

| # | Inspection Item | Verification Result & Mitigation | Severity |
|:---:|---|---|:---:|
| 1 | **Clock-Domain Consistency** | All blocks operate synchronously on `HCLK` (100 MHz). No CDC. | **No issue** |
| 2 | **Reset Polarity** | All blocks use active-low asynchronous reset (`!rst_n` / `!HRESETn`). | **No issue** |
| 3 | **Multiple Drivers** | All internal signals have strictly one source. SCL/SDA drives are multiplexed within `i2c_master.sv`. | **No issue** |
| 4 | **Undriven Signals** | `ctrl_int_enable_o` is exported by `i2c_registers` but consumed internally for `irq_o`. At the top level, it can remain unconnected without affecting functionality. | **No issue** |
| 5 | **Port-Width Mismatches** | All interconnect buses (32-bit data, 8-bit addr, 16-bit clock counts, 32-bit timeout) match 100%. | **No issue** |
| 6 | **Register Address Decoding** | Word-aligned decoding verified for 0x00, 0x04, 0x08, 0x0C, 0x10, 0x14, 0x18, 0x1C. | **No issue** |
| 7 | **TX_DATA / RX_DATA Handshake** | TX holding buffer empty flag (`hw_tx_empty_o`) and read-on-clear RX valid flag (`stat_rx_valid_q`) verified. | **No issue** |
| 8 | **COMMAND Strobes** | Active-high 1-cycle pulses generated upon AHB write to `ADDR_COMMAND` (0x14). | **No issue** |
| 9 | **TIMEOUT Connection** | Full 32-bit `TIMEOUT` register (0x18) connected directly to `i2c_timeout`. | **No issue** |
| 10 | **IRQ & STATUS Feedback** | Hardware status updates with hardware-priority W1C clearing verified. | **No issue** |
| 11 | **Open-Drain Connections** | Active-low drive signals float the bus on deassertion. Zero active HIGH drive. | **No issue** |
| 12 | **Clock Gen Abort Connection** | `timeout_event` triggers `cg_abort` internally within `i2c_master.sv`, forcing immediate clean IDLE state. | **No issue** |
| 13 | **Timeout Event Priority** | Top-level precedence in sequential block ensures immediate abort override. | **No issue** |
| 14 | **AHB Read/Write Handshake** | Pipelined address/data phases with `HREADY` sampling verified against AHB-Lite protocol standard. | **No issue** |

---

## 9. Categorization of Unresolved Issues

- **Critical Issues (prevents integration):**
  - **NONE.** All required signals exist, port widths match, and clock/reset semantics are unified.
- **Major Issues (likely functional issue):**
  - **NONE.** All functional handshakes and protocols have been validated across Tasks A, B, C, and D.
- **Minor Issues (documentation / style):**
  - `ctrl_int_enable_o` is exposed on `i2c_registers` but not required by `i2c_master` (it is already used internally inside `i2c_registers` to generate `irq_o`). This output will be left unconnected at the top-level wire list.
  - Reset port names differ across submodules (`HRESETn` in AHB, `rst_n` in registers/master, `reset_n` in clock_gen/timeout). Handled trivially by port mapping.
- **No Issue (verified connections):**
  - All 43 point-to-point connections listed in Section 4 are verified and ready for instantiation.

---

## 10. Final Recommendation

1. **Architecture Readiness:** The RTL modules are **100% READY** for top-level integration.
2. **Proposed Top-Level Module:** Implement `rtl/i2c_master_top.sv` instantiating:
   - `ahb_lite_slave_if u_ahb_slave`
   - `i2c_registers u_registers`
   - `i2c_master u_master`
3. **Freeze Status:** All existing RTL files in `rtl/` remain strictly unmodified.
4. **Next Step:** Await user approval of this Step 1 inspection report before authoring `rtl/i2c_master_top.sv` in Step 2.
