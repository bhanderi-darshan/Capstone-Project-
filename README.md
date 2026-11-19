# Design and Verification of an AHB-Lite Based I²C Master Controller with Programmable Clock Generation and Hardware Clock-Stretching Timeout

[![SystemVerilog](https://img.shields.io/badge/Language-SystemVerilog%20IEEE%201800--2012-blue.svg)](#)
[![Simulation](https://img.shields.io/badge/Simulator-Icarus%20Verilog%2012.0-green.svg)](#)
[![Verification](https://img.shields.io/badge/Verification-293%2F293%20Passed%20(100%25)-brightgreen.svg)](#)
[![Bus Protocol](https://img.shields.io/badge/Bus-AHB--Lite%20v1.0-orange.svg)](#)
[![I2C Spec](https://img.shields.io/badge/I2C-UM10204%20Standard%2FFast-yellow.svg)](#)
[![Target](https://img.shields.io/badge/Target-FPGA%20%2F%20ASIC%20GDSII-purple.svg)](#)

---

## 1. Project Title
**Design and Verification of an AHB-Lite Based I²C Master Controller with Programmable Clock Generation and Hardware Clock-Stretching Timeout**  
*Final-Year VLSI Capstone Engineering Project*  
**Author:** Darshan Bhanderi ([@bhanderi-darshan](https://github.com/bhanderi-darshan))  
**Primary Specification:** `Darshan_Project_doc.pdf`  

---

## 2. Project Overview
This repository contains a production-grade, fully synthesizable SystemVerilog implementation and self-checking verification environment for an **AHB-Lite to I²C Master Controller IP**. Designed for integration into modern System-on-Chip (SoC) architectures, the IP provides an AMBA AHB-Lite 32-bit slave interface through which an embedded processor or DMA engine can configure, initiate, and monitor standard I²C bus transactions.

Key architectural highlights include:
- Fully programmable SCL clock generation supporting **Standard Mode (100 kHz)**, **Fast Mode (400 kHz)**, and custom asymmetric frequencies from a **100 MHz HCLK** system clock.
- Dedicated **Hardware Clock-Stretching Timeout Detection** counter preventing SoC bus deadlocks when an external I²C slave hangs SCL low.
- Unified 8-word memory-mapped register interface with single-cycle command strobes, status tracking, read-on-clear logic, and Write-1-to-Clear (W1C) interrupt management.
- Self-contained open-drain bi-directional I/O pad logic with internal two-stage synchronizers on both SCL and SDA inputs.
- Comprehensive verification environment achieving **293 out of 293 passing dynamic assertions** across unit, core, and full-chip regression suites.

---

## 3. Problem Statement
In multi-voltage SoC architectures, the I²C bus remains one of the most widely used low-speed interfaces for communicating with sensors, power management ICs (PMICs), RTCs, and EEPROMs. However, standard I²C controller implementations suffer from two critical architectural shortcomings:
1. **Clock Stretching Bus Lockups:** When a slave holds SCL low to request processing time, a malfunctioning or disconnected slave can hang the SCL line indefinitely. Traditional controllers either hang waiting for SCL or require complex software watchdog timers that consume processor overhead and cannot cleanly recover the hardware state machine.
2. **Fixed Frequency Inflexibility:** Many legacy controllers use hardcoded divider ratios that cannot adapt to non-standard bus loadings, varying rise times, or asymmetrical high/low phase requirements needed to meet minimum $t_{HIGH}$ and $t_{LOW}$ timings under heavy capacitive load.

This project solves both problems through a dedicated, hardware-managed exact-N timeout engine and a fully programmable dual half-cycle divider.

---

## 4. Project Objectives
- **Synthesizable SystemVerilog RTL:** Implement a clean, modular, lint-clean SystemVerilog design suitable for ASIC and FPGA synthesis.
- **AHB-Lite Slave Protocol Compliance:** Provide zero-wait-state memory-mapped register access using standard 32-bit pipelined transfers (`HADDR`, `HWDATA`, `HRDATA`, `HTRANS`, `HWRITE`, `HSEL`, `HREADY`).
- **Full I²C Protocol Support:** 7-bit addressing, START, Repeated START, STOP, byte writes with slave ACK/NACK detection, byte reads with master NACK, and automatic abort on NACK.
- **Programmable Clock Generator:** Independent 16-bit high and low counters allowing fine-grained asymmetric duty-cycle tuning and proper bus-free ($t_{BUF}$) qualification.
- **Deterministic Hardware Timeout:** Programmable 32-bit timeout counter operating from 100 MHz HCLK, providing single-cycle error pulse generation, immediate FSM abort to IDLE, clock generator reset, and bus release.
- **Complete Self-Checking Verification:** Rigorous modular testbenches utilizing cycle-accurate slave BFMs, clock-stretching fault injectors, and deterministic assertions.

---

## 5. Main Features

| Feature Category | Technical Specification |
|:---|:---|
| **System Clock** | 100 MHz HCLK ($T_{clk} = 10.0\text{ ns}$) |
| **Host Bus Interface** | 32-bit AMBA AHB-Lite v1.0 Slave (Zero Wait States for registers) |
| **I²C Operating Modes** | Standard Mode (100 kHz), Fast Mode (400 kHz), Custom Speeds |
| **Addressing Modes** | 7-bit Slave Addressing (transmitted via `TX_DATA` register) |
| **Transaction Modes** | Single-byte write, multi-byte burst write, single-byte read, Repeated START |
| **Clock Generation** | Independent 16-bit `HIGH_COUNT` and `LOW_COUNT` divider counters |
| **Clock Stretching** | Hardware SCL synchronization wait-state in clock generator |
| **Timeout Handling** | Programmable 32-bit exact-N counter; priority abort to IDLE; bus release |
| **Interrupts** | Unified active-high `irq_o` output; individual enables for DONE, ACK_ERROR, TIMEOUT |
| **Fault Recovery** | Auto-abort on address/data NACK; timeout abort; clean recovery without reset |
| **Physical I/O** | True open-drain drive (`scl_drive_low`, `sda_drive_low`) with dual-flop synchronizers |

---

## 6. System Architecture

The IP comprises three primary peer modules integrated inside `i2c_master_top`:
1. `ahb_lite_slave_if`: Bridges external AHB-Lite bus transfers into synchronous internal register read/write strobes.
2. `i2c_registers`: Houses the 8 memory-mapped registers, control decoding, interrupt logic, and status registers.
3. `i2c_master`: Implements the 12-state I²C protocol FSM, instantiating the programmable clock generator (`i2c_clock_gen`) and hardware timeout engine (`i2c_timeout`).

```
+----------------------------------------------------------------------------------------------------+
|                                         i2c_master_top                                             |
|                                                                                                    |
|   AHB-Lite Bus               +--------------------+                  +-------------------------+   |
|   ========================>  |                    |  reg_write_en    |                         |   |
|   HADDR, HWDATA, HSEL,       | ahb_lite_slave_if  |  reg_read_en     |      i2c_registers      |   |
|   HTRANS, HWRITE, HREADY     |                    |===============>  |                         |   |
|   <========================  |                    |  reg_addr, wdata |                         |   |
|   HRDATA, HREADYOUT, HRESP   +--------------------+  <=============  +-------------------------+   |
|                                                         reg_rdata          ||  ||  ||              |
|                                                                ctrl/div/tx ||  ||  || stat/rx/irq  |
|                                                                            \/  \/  \/              |
|                                                              +-------------------------+           |
|                                                              |       i2c_master        |           |
|                                                              |                         |           |
|                                                              |  +-------------------+  |           |
|                                                              |  |   i2c_clock_gen   |  |           |
|                                                              |  +-------------------+  |           |
|                                                              |  |    i2c_timeout    |  |           |
|                                                              |  +-------------------+  |           |
|                                                              +-------------------------+           |
|                                                                     ||         ||                  |
|                                                     scl_drive_low / in ||         || sda_drive_low/in |
|                                                                     \/         \/                  |
|                                                             +---------------------------+          |
|                                                             | Bi-directional Pad Logic  |          |
|                                                             | & Two-Stage Synchronizers |          |
|                                                             +---------------------------+          |
|                                                                    ||          ||                  |
|                                                                  scl_io      sda_io                |
+--------------------------------------------------------------------||----------||------------------+
                                                                     ||          ||
                                                                  [Pullup]    [Pullup]
                                                                     ||          ||
                                                                Physical I2C Open-Drain Bus
```

---

## 7. Block Diagram

### Internal Master Hierarchy & Datapath
```
                     +---------------------------------------------+
                     |                 i2c_master                  |
                     |                                             |
                     |  +---------------------------------------+  |
                     |  |           12-State FSM Core           |  |
                     |  |  (IDLE, START, ADDR, WRITE, READ,     |  |
                     |  |   RESTART, STOP, ACK checks, READY)   |  |
                     |  +---------------------------------------+  |
                     |         |                 |          ^      |
                     |         | cg_start        | timeout  |      |
                     |         v                 v          |      |
                     |  +---------------+  +--------------+ |      |
                     |  | i2c_clock_gen |  | i2c_timeout  | |      |
                     |  | (HIGH / LOW   |  | (Exact-N     | |      |
                     |  |  Counters)    |  |  Detection)  | |      |
                     |  +---------------+  +--------------+ |      |
                     |         |                 |          |      |
                     |         +--------+--------+          |      |
                     |                  |                   |      |
                     |                  v                   |      |
                     |          +-------------------+       |      |
                     |          | Pad Output Logic  |       |      |
                     |          | & 2-Stage Sync    |-------+      |
                     |          +-------------------+              |
                     +---------------------------------------------+
```

---

## 8. Module-Wise Description

### 8.1 Frozen Task A–D RTL Modules
The core architecture consists of six modules verified and frozen during Tasks A through D:
1. **`rtl/i2c_pkg.sv`**: Defines package constants, address offsets, bit masks, reset defaults, and the 12-state FSM enumerated type (`i2c_state_t`).
2. **`rtl/ahb_lite_slave_if.sv`**: Implements the AHB-Lite bus interface. Translates address and data phases into single-cycle synchronous register accesses with zero wait states (`HREADYOUT = 1`, `HRESP = OKAY`).
3. **`rtl/i2c_registers.sv`**: 8-word memory-mapped register bank. Manages software-driven command strobes, hardware status updates, interrupt pending latches with Write-1-to-Clear (W1C) priority, and `RX_DATA` read-on-clear logic.
4. **`rtl/i2c_clock_gen.sv`**: Half-cycle clock counter generating SCL timing. Incorporates clock-stretching detection (waiting in `STATE_WAIT_SCL_HIGH` until physical SCL rises) and synchronous abort support.
5. **`rtl/i2c_timeout.sv`**: Hardware clock-stretching watchdog counter. Counts qualifying HCLK cycles when SCL is expected HIGH but held LOW by an external slave. Generates a 1-cycle `timeout_event` pulse on the exact $N$-th cycle.
6. **`rtl/i2c_master.sv`**: Top-level protocol controller coordinating framing, 8-bit shift registers, ACK/NACK evaluation, bus-free detection ($t_{BUF}$), and immediate abort routing.

### 8.2 Task E Top-Level Integration Module
- **`rtl/i2c_master_top.sv`**: Top-level structural wrapper interconnecting `ahb_lite_slave_if`, `i2c_registers`, and `i2c_master`. Contains bi-directional open-drain tri-state pads (`scl_io = scl_drive_low ? 1'b0 : 1'bz`) and two-stage flip-flop synchronizers for meta-stability prevention on physical inputs.

---

## 9. Register Map

All registers are 32-bit word-aligned with base offsets detailed below:

| Register Name | Offset | Access | Reset Value | Description |
|:---|:---:|:---:|:---:|:---|
| **CONTROL** | `0x00` | R/W | `0x00000000` | Controller configuration (Enable, Interrupt Enable, Auto-STOP) |
| **STATUS** | `0x04` | RO | `0x00000002` | Hardware status flags (`TX_EMPTY = 1` at reset) |
| **CLOCK_DIV** | `0x08` | R/W | `0x01F401F4` | SCL clock dividers: `[15:0] HIGH_COUNT`, `[31:16] LOW_COUNT` |
| **TX_DATA** | `0x0C` | R/W | `0x00000000` | Transmit holding register (Slave address byte or payload data byte) |
| **RX_DATA** | `0x10` | RO | `0x00000000` | Received data byte (Reading clears `STATUS.RX_VALID`) |
| **COMMAND** | `0x14` | WO | `0x00000000` | 1-cycle command strobes (START, WRITE, READ, STOP, RESTART) |
| **TIMEOUT** | `0x18` | R/W | `0x000186A0` | Hardware timeout limit (100,000 cycles = 1.0 ms default; 0 = Disabled) |
| **IRQ** | `0x1C` | R/W1C | `0x00000000` | Interrupt status (W1C pending flags `[2:0]`, interrupt enables `[10:8]`) |

### Detailed Bitfield Specifications

#### CONTROL (Offset `0x00`)
- `Bit 0`: `ENABLE` — 1: Enable I²C controller; 0: Disable and reset FSM to IDLE.
- `Bit 1`: `INT_ENABLE` — 1: Global interrupt output `irq_o` enabled; 0: Masked.
- `Bit 2`: `AUTO_STOP` — 1: Automatically issue STOP after byte transfer (ignored on Address byte).

#### STATUS (Offset `0x04`)
- `Bit 0`: `BUSY` — 1: Transaction in progress; 0: Bus IDLE.
- `Bit 1`: `TX_EMPTY` — 1: TX holding register ready for next byte; 0: TX register full.
- `Bit 2`: `RX_VALID` — 1: Received byte available in `RX_DATA`; cleared on reading `RX_DATA`.
- `Bit 3`: `ACK_ERROR` — 1: Slave NACK received; latches until next command write.
- `Bit 4`: `TIMEOUT_ERROR` — 1: Clock-stretching timeout occurred; latches until next command write.
- `Bit 5`: `DONE` — 1: Operation completed successfully; cleared on next command write.

#### CLOCK_DIV (Offset `0x08`)
- `Bits [15:0]`: `HIGH_COUNT` — Half-period count for SCL HIGH phase ($N_{HIGH} \ge 1$).
- `Bits [31:16]`: `LOW_COUNT` — Half-period count for SCL LOW phase ($N_{LOW} \ge 1$).

#### COMMAND (Offset `0x14` - Write-Only Strobes)
- `Bit 0`: `CMD_START` — Generate START condition.
- `Bit 1`: `CMD_WRITE` — Transmit byte currently in `TX_DATA` onto I²C bus.
- `Bit 2`: `CMD_READ` — Receive 1 byte from slave and generate Master NACK.
- `Bit 3`: `CMD_STOP` — Generate STOP condition and release bus.
- `Bit 4`: `CMD_RESTART` — Generate Repeated START condition without issuing STOP.

#### IRQ (Offset `0x1C` - Unified Status & Enable)
- `Bit 0`: `DONE_PENDING` — Latches 1 on `hw_done_o`. Write 1 to clear (W1C).
- `Bit 1`: `ACK_ERROR_PENDING` — Latches 1 on `hw_ack_error_o`. Write 1 to clear (W1C).
- `Bit 2`: `TIMEOUT_PENDING` — Latches 1 on `hw_timeout_error_o`. Write 1 to clear (W1C).
- `Bit 8`: `DONE_ENABLE` — 1: Enable interrupt generation on `DONE`.
- `Bit 9`: `ACK_ERROR_ENABLE` — 1: Enable interrupt generation on `ACK_ERROR`.
- `Bit 10`: `TIMEOUT_ENABLE` — 1: Enable interrupt generation on `TIMEOUT`.

---

## 10. AHB-Lite Interface Description
The controller adheres strictly to the AMBA 3 AHB-Lite v1.0 protocol:
- **Zero Wait-State Transfers:** All memory-mapped register reads and writes execute with zero wait states (`HREADYOUT = 1'b1`, `HRESP = 1'b0`).
- **Pipelined Phasing:** Address phase signals (`HADDR`, `HSEL`, `HTRANS`, `HWRITE`) are sampled on the rising edge of `HCLK`. Data phase (`HWDATA` / `HRDATA`) executes on the subsequent clock cycle.
- **Robust Unmapped Access:** Reading or writing unmapped offsets within the peripheral space returns `HRESP = OKAY` (0) and read data `32'h00000000` without corrupting internal peripheral states.

---

## 11. I²C Operation
1. **START Framing:** Prior to START, the controller verifies bus-free status ($t_{BUF}$) by counting consecutive cycles where physical SCL and SDA are both HIGH. SDA transitions LOW while SCL remains HIGH.
2. **Address & Data Transmission:** Data is driven MSB first onto SDA during SCL LOW. SCL transitions HIGH, where data remains stable. On the 9th clock cycle, the master releases SDA and samples slave ACK/NACK.
3. **NACK Auto-Abort:** If a slave generates a NACK on address or data, `STATUS.ACK_ERROR` asserts, `hw_done_o` is suppressed, and the controller automatically executes an abort STOP sequence to release the bus safely.
4. **Data Reception:** During reads, the master releases SDA to allow the slave to drive payload bits. On the 9th cycle, the master transmits a Master NACK (leaves SDA HIGH) and sets `STATUS.RX_VALID = 1`.
5. **Repeated START:** Supports multi-phase read/write operations by transitioning SDA from HIGH to LOW while SCL is held HIGH, without releasing the bus to IDLE.
6. **STOP Framing:** SDA transitions from LOW to HIGH while SCL remains HIGH, returning both lines to High-Z.

---

## 12. Programmable Clock Generation
The I²C clock frequency is synthesized from `HCLK` (100 MHz = 10 ns period) using the `CLOCK_DIV` register:
$$F_{SCL} = \frac{F_{HCLK}}{\text{LOW\_COUNT} + \text{HIGH\_COUNT}}$$

### Standard Configurations
- **Standard Mode (100 kHz):**
  - $\text{LOW\_COUNT} = 500\text{ cycles } (5.0\ \mu\text{s})$, $\text{HIGH\_COUNT} = 500\text{ cycles } (5.0\ \mu\text{s})$.
  - `CLOCK_DIV = 0x01F401F4`. Period = $10.0\ \mu\text{s}$ (100.0 kHz). Meets $t_{LOW} \ge 4.7\ \mu\text{s}$, $t_{HIGH} \ge 4.0\ \mu\text{s}$.
- **Fast Mode (400 kHz):**
  - $\text{LOW\_COUNT} = 130\text{ cycles } (1.3\ \mu\text{s})$, $\text{HIGH\_COUNT} = 120\text{ cycles } (1.2\ \mu\text{s})$.
  - `CLOCK_DIV = 0x00820078`. Period = $2.5\ \mu\text{s}$ (400.0 kHz). Meets $t_{LOW} \ge 1.3\ \mu\text{s}$, $t_{HIGH} \ge 0.6\ \mu\text{s}$.

### Hardware SCL Synchronization
During the SCL HIGH phase, the clock generator releases SCL and monitors the synchronized input `scl_sync`. If an external slave holds SCL LOW (clock stretching), the clock generator suspends its HIGH counter and remains in `STATE_WAIT_SCL_HIGH`. The HIGH count begins only after physical SCL is sampled HIGH.

---

## 13. Clock-Stretching Timeout
To prevent system hang conditions caused by unresponsive or damaged slave devices:
1. **Exact-N Qualification:** When SCL is released HIGH by the master but held LOW by a slave, the `i2c_timeout` counter increments on every rising edge of `HCLK`.
2. **Deterministic Trigger:** When the counter reaches exactly `TIMEOUT` qualifying cycles:
   - A single-cycle `hw_timeout_error_o` pulse is generated.
   - Master FSM aborts immediately to `ST_IDLE`.
   - Clock generator is forced out of `STATE_WAIT_SCL_HIGH` to `STATE_IDLE`.
   - `STATUS.TIMEOUT_ERROR` and `IRQ.TIMEOUT_PENDING` assert.
   - `hw_busy_o` returns to 0 and all line drives are released.
3. **Disabling Feature:** Setting `TIMEOUT = 0` completely disables timeout detection.

---

## 14. Verification Methodology
The verification environment is architected using self-checking SystemVerilog testbenches with deterministic assertions:
- **Layered Protocol Drivers:** Standard AHB-Lite bus transaction tasks (`ahb_write_reg`, `ahb_read_reg`) mimic CPU bus masters.
- **Cycle-Accurate Slave BFM:** `i2c_slave_model` simulates an I²C slave (`7'h50`) with programmable ACK/NACK generation, clock stretching injection, and receive/transmit data checking.
- **Open-Drain Simulation:** Verilog `pullup (scl); pullup (sda);` primitives model physical pull-up resistors on bi-directional open-drain lines.
- **Negative & Corner-Case Testing:** Tests cover bus-busy rejection, premature START suppression, address NACK, data NACK, repeated START without STOP, clock-stretching tolerance, timeout aborts, and post-timeout recovery without reset.

---

## 15. Simulation Results

### Verification Summary Scoreboard

| Suite | Target Module(s) | Testbench File | Executed Checks | Passed | Failed | Status |
|:---|:---|:---|:---:|:---:|:---:|:---:|
| **Task A** | `ahb_lite_slave_if`, `i2c_registers` | [`tb/tb_ahb_registers.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/tb/tb_ahb_registers.sv) | 46 | 46 | 0 | **PASS** |
| **Task B** | `i2c_clock_gen` | [`tb/tb_i2c_clock_gen.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/tb/tb_i2c_clock_gen.sv) | 49 | 49 | 0 | **PASS** |
| **Task D Unit** | `i2c_timeout` | [`tb/tb_i2c_timeout.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/tb/tb_i2c_timeout.sv) | 37 | 37 | 0 | **PASS** |
| **Tasks C & D** | `i2c_master` (integrated core) | [`tb/tb_i2c_master.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/tb/tb_i2c_master.sv) | 93 | 93 | 0 | **PASS** |
| **Task E Top** | `i2c_master_top` (full chip) | [`tb/tb_i2c_master_top.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/tb/tb_i2c_master_top.sv) | 68 | 68 | 0 | **PASS** |
| **TOTAL** | **Full Project Verification** | **All 5 Test Suites** | **293** | **293** | **0** | **PASS (100%)** |

*(Note: The baseline Task C testbench log showing 62 checks is preserved under `sim/task_c_simulation.log` as supplementary historical evidence; the 93 checks in `sim/task_d_simulation.log` represent the complete integrated master core verification).*

All results are backed by verified simulation logs in [`sim/`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/sim/).

---

## 16. Software and Tool Requirements
- **Simulator:** Icarus Verilog (`iverilog` version 11.0 or higher with IEEE 1800-2012 SystemVerilog support).
- **Simulation Runner:** `vvp` (Icarus Verilog simulation engine).
- **Waveform Viewer:** GTKWave (optional, for viewing `.vcd` files).
- **Shell / Scripting:** Bash (Linux/Ubuntu/macOS) or PowerShell / Command Prompt (Windows).

---

## 17. Ubuntu / Linux Setup Instructions

```bash
# 1. Update package manager
sudo apt-get update

# 2. Install Icarus Verilog and GTKWave
sudo apt-get install -y iverilog gtkwave git

# 3. Clone the repository
git clone https://github.com/bhanderi-darshan/Capstone-Project-.git
cd Capstone-Project-

# 4. Make simulation scripts executable
chmod +x sim/*.sh
```

---

## 18. Compilation and Simulation Commands

### 18.1 Run Complete Regression Suite (All 293 Checks)
#### On Linux / Ubuntu:
```bash
./sim/run_all_regressions.sh
```
#### On Windows:
```cmd
sim\run_all_regressions.bat
```

### 18.2 Running Individual Testbenches

#### Full-Chip Top-Level Integration (Task E - 68 Checks)
```bash
iverilog -g2012 -Wall -o sim/tb_i2c_master_top.vvp \
  rtl/i2c_pkg.sv rtl/ahb_lite_slave_if.sv rtl/i2c_registers.sv rtl/i2c_clock_gen.sv \
  rtl/i2c_timeout.sv rtl/i2c_master.sv rtl/i2c_master_top.sv tb/i2c_slave_model.sv tb/tb_i2c_master_top.sv
vvp sim/tb_i2c_master_top.vvp
```

#### Master Controller Core Regression (Tasks C & D - 93 Checks)
```bash
iverilog -g2012 -Wall -o sim/tb_i2c_master.vvp \
  rtl/i2c_pkg.sv rtl/i2c_clock_gen.sv rtl/i2c_timeout.sv rtl/i2c_master.sv \
  rtl/i2c_registers.sv tb/i2c_slave_model.sv tb/tb_i2c_master.sv
vvp sim/tb_i2c_master.vvp
```

#### AHB Slave & Registers Verification (Task A - 46 Checks)
```bash
iverilog -g2012 -Wall -o sim/tb_ahb_registers.vvp \
  rtl/i2c_pkg.sv rtl/ahb_lite_slave_if.sv rtl/i2c_registers.sv tb/tb_ahb_registers.sv
vvp sim/tb_ahb_registers.vvp
```

#### Programmable Clock Generator Unit (Task B - 49 Checks)
```bash
iverilog -g2012 -Wall -o sim/tb_i2c_clock_gen.vvp rtl/i2c_clock_gen.sv tb/tb_i2c_clock_gen.sv
vvp sim/tb_i2c_clock_gen.vvp
```

#### Hardware Timeout Unit (Task D - 37 Checks)
```bash
iverilog -g2012 -Wall -o sim/tb_i2c_timeout.vvp rtl/i2c_timeout.sv tb/tb_i2c_timeout.sv
vvp sim/tb_i2c_timeout.vvp
```

---

## 19. Project Directory Structure

```
Capstone-Project-/
│
├── README.md                          # Master GitHub documentation
├── .gitignore                         # Git tracking exclusion rules
│
├── docs/                              # Comprehensive architectural & task reports
│   ├── project_specification.md       # High-level engineering specification
│   ├── architecture.md                # System & sub-module architectural details
│   ├── register_map.md                # Detailed register manual
│   ├── verification_summary.md        # Consolidated 293-check scoreboard report
│   ├── task_b_design_notes.md         # Task B clock generator design notes
│   ├── task_c_design_notes.md         # Task C master controller design notes
│   ├── task_d_final_audit.md          # Task D timeout formal audit report
│   ├── task_d_timeout_design_notes.md # Task D timeout design notes
│   ├── task_e_step1_rtl_interface.md  # Task E Step 1 interface inspection
│   ├── task_e_step2_top_level.md      # Task E Step 2 top-level architecture
│   ├── task_e_step3_verification.md   # Task E Step 3 full-chip verification report
│   └── references/                    # Original text extractions of project doc
│       ├── darshan_deciphered.txt
│       └── darshan_extracted.txt
│
├── rtl/                               # Synthesizable SystemVerilog RTL
│   ├── i2c_pkg.sv                     # [FROZEN] Package definitions and FSM states
│   ├── ahb_lite_slave_if.sv           # [FROZEN] AHB-Lite 32-bit slave adapter
│   ├── i2c_registers.sv               # [FROZEN] Memory-mapped register bank
│   ├── i2c_clock_gen.sv               # [FROZEN] SCL programmable clock generator
│   ├── i2c_timeout.sv                 # [FROZEN] Hardware clock-stretching timeout unit
│   ├── i2c_master.sv                  # [FROZEN] Core 12-state I2C master FSM
│   └── i2c_master_top.sv              # Synthesizable top-level integration module
│
├── tb/                                # Verification testbenches and models
│   ├── ahb_tasks.svh                  # Reusable AHB-Lite driver task library
│   ├── i2c_slave_model.sv             # Cycle-accurate I2C slave BFM (7'h50)
│   ├── tb_ahb_registers.sv            # Task A testbench (46 checks)
│   ├── tb_i2c_clock_gen.sv            # Task B testbench (49 checks)
│   ├── tb_i2c_timeout.sv              # Task D unit testbench (37 checks)
│   ├── tb_i2c_master.sv               # Tasks C & D integration testbench (93 checks)
│   └── tb_i2c_master_top.sv           # Task E full-chip testbench (68 checks)
│
├── sim/                               # Simulation automation and logs
│   ├── filelist.f                     # Icarus Verilog argument file
│   ├── run_all_regressions.bat        # Automated regression runner for Windows
│   ├── run_all_regressions.sh         # Automated regression runner for Linux/macOS
│   ├── run_phase1.bat                 # Phase 1 Windows script
│   ├── run_phase1.sh                  # Phase 1 Linux script
│   ├── task_a_simulation.log          # 46 checks passed
│   ├── task_b_simulation.log          # 49 checks passed
│   ├── task_c_simulation.log          # 62 checks passed (baseline)
│   ├── task_d_simulation.log          # 93 checks passed (integrated)
│   ├── task_d_timeout_unit_simulation.log # 37 checks passed
│   └── task_e_top_simulation.log      # 68 checks passed (full-chip)
│
├── fpga/                              # FPGA implementation directory
│   └── README.md                      # FPGA integration & platform evaluation guide
│
├── asic/                              # ASIC implementation directory
│   └── README.md                      # ASIC physical design & synthesis guide
│
└── tools/                             # Automation scripts
    └── README.md                      # Tooling instructions & environment setup
```

---

## 20. FPGA Implementation Status
- **Status:** **RTL Synthesizable & Architecture Validated** (Physical FPGA demonstration planned as a subsequent project milestone).
- **Platform Portability:** The design uses strictly synchronous SystemVerilog with internal two-flop synchronizers and avoids vendor-specific IP primitives, allowing direct synthesis across any modern FPGA family.
- **Candidate Target Platforms (Under Evaluation):**
  - Xilinx Artix-7 (e.g., Basys-3 / Nexys-4) via Vivado Design Suite.
  - Intel Cyclone IV / Cyclone V via Intel Quartus Prime.
- **External Pin Requirements:** Requires external $2.2\ \text{k}\Omega\text{ to }4.7\ \text{k}\Omega$ pull-up resistors on the target board's PMOD / GPIO header pins connected to `scl_io` and `sda_io`.

---

## 21. ASIC Implementation Status
- **Status:** **ASIC-Ready Architecture** (Physical GDSII tapeout flow planned as a subsequent project milestone).
- **Design Constraints:** 
  - Standard cell library compatible (zero internal tri-state buses).
  - Bi-directional open-drain pads implemented using top-level output enables (`scl_drive_low ? 1'b0 : 1'bz`) easily mapped to standard I/O pad cells (e.g., `sky130_fd_io__top_gpiov2`).
  - Target Clock: 100 MHz HCLK ($T_{period} = 10.0\text{ ns}$). Easily achieves timing closure on mature 180nm, 130nm, or 65nm CMOS nodes.
- **Candidate ASIC Flows (Under Evaluation):**
  - OpenLane / SkyWater 130nm open-source ASIC flow.
  - Synopsys Design Compiler + IC Compiler II flow.

---

## 22. Future Work
- **Direct Memory Access (DMA) Integration:** Add AHB burst and DMA handshake request lines for high-throughput sensor logging without CPU polling.
- **Multi-Master Arbitration:** Implement bus arbitration and clock synchronization for multi-master topologies.
- **10-Bit Addressing:** Extend the FSM to support 10-bit slave addressing headers (`11110xx`).
- **High-Speed Mode (3.4 MHz):** Implement current-source pull-up support for I²C High-Speed mode.

---

## 23. References
1. **Primary Project Specification:** `Darshan_Project_doc.pdf` (Final-Year VLSI Design Project Specification).
2. **I²C Protocol Specification:** NXP Semiconductors, *UM10204: I²C-bus specification and user manual*, Rev. 7.0.
3. **AHB-Lite Protocol Specification:** ARM Limited, *AMBA 3 AHB-Lite Protocol Specification*, v1.0 (ARM IHI 0033A).
4. **SystemVerilog Standard:** IEEE Computer Society, *IEEE Standard for SystemVerilog—Unified Hardware Design, Specification, and Verification Language*, IEEE Std 1800-2012.

---

## 24. Author and Project Information
- **Project Title:** Design and Verification of an AHB-Lite Based I²C Master Controller with Programmable Clock Generation and Hardware Clock-Stretching Timeout
- **Author:** Darshan Bhanderi
- **GitHub:** [@bhanderi-darshan](https://github.com/bhanderi-darshan)
- **Repository:** [Capstone-Project-](https://github.com/bhanderi-darshan/Capstone-Project-)
- **Degree Program:** Final-Year Bachelor of Engineering in Electronics & Communication / VLSI Engineering
