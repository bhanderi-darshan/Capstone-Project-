# Project Engineering Specification

**Project:** Design and Verification of an AHB-Lite Based I²C Master Controller with Programmable Clock Generation and Hardware Clock-Stretching Timeout  
**Author:** Darshan Bhanderi  
**Authority:** Derived from primary project document `Darshan_Project_doc.pdf`  
**Standard:** IEEE 1800-2012 SystemVerilog / AMBA 3 AHB-Lite v1.0 / NXP UM10204 I²C  

---

## 1. System Requirements & Functional Scope

### 1.1 Primary Objectives
The objective of this project is to architect, implement in synthesizable SystemVerilog, and verify a complete I²C Master Controller IP that connects to a host system via an AMBA AHB-Lite 32-bit bus interface.

The design specifically addresses two critical industrial requirements:
1. **Clock-Stretching Robustness:** A slave holding SCL LOW must not cause an unrecoverable system bus lockup. The controller must provide a hardware-managed exact-N timeout engine that safely returns the master FSM to IDLE and releases the physical lines.
2. **Frequency Agility:** The controller must support fine-grained duty-cycle and frequency tuning across Standard Mode (100 kHz) and Fast Mode (400 kHz) using independent HIGH and LOW half-cycle counters operating from a 100 MHz system clock.

---

## 2. Operational Parameters

| Parameter | Specification | Units / Description |
|:---|:---:|:---|
| **System Clock ($F_{HCLK}$)** | 100.0 | MHz ($T_{HCLK} = 10.0\text{ ns}$) |
| **System Reset ($HRESETn$)** | Active-Low | Asynchronous assertion, synchronous deassertion |
| **AHB-Lite Data Width** | 32 | Bits |
| **AHB-Lite Address Width** | 32 | Bits (Byte addresses, word-aligned accesses) |
| **I²C Physical Lines** | 2 | `scl_io` (Serial Clock), `sda_io` (Serial Data) |
| **I²C Physical Drive Mode** | Open-Drain | Active drive LOW (`0`), High-Z passive pull-up (`1`) |
| **External Pull-Up Resistance** | 2.0 to 4.7 | $\text{k}\Omega$ (nominal, dependent on bus capacitance) |
| **I²C Addressing Mode** | 7 | Bits (Standard 7-bit slave address) |
| **I²C Supported Speeds** | 100 / 400 | kHz (Standard Mode / Fast Mode) |
| **Timeout Counter Resolution** | 1 | HCLK cycle (10.0 ns) |
| **Timeout Default Limit** | 100,000 | Cycles (1.0 ms at 100 MHz HCLK) |

---

## 3. Bus Interface Specifications

### 3.1 AMBA AHB-Lite Slave Interface
The controller acts as an AHB-Lite slave. The interface signals are:
- `HCLK`: System clock input (100 MHz).
- `HRESETn`: Active-LOW system reset.
- `HSEL`: Peripheral slave select.
- `HADDR [31:0]`: Transfer address bus.
- `HTRANS [1:0]`: Transfer type (`2'b00` = IDLE, `2'b10` = NONSEQ, `2'b11` = SEQ).
- `HWRITE`: Transfer direction (1 = Write, 0 = Read).
- `HWDATA [31:0]`: Write data bus.
- `HRDATA [31:0]`: Read data bus.
- `HREADY`: Global bus ready input from arbiter.
- `HREADYOUT`: Slave ready output (always driven to `1'b1` for zero wait states).
- `HRESP`: Transfer response (always driven to `1'b0` = `OKAY`).

### 3.2 System Interrupt Interface
- `irq_o`: Active-HIGH level-sensitive interrupt line. Driven to `1` when any enabled pending event (`DONE`, `ACK_ERROR`, `TIMEOUT`) is active and global interrupt enable (`CONTROL.INT_ENABLE`) is set.

---

## 4. Register Specification

The IP defines 8 memory-mapped 32-bit registers located at 4-byte boundaries:

```
Offset 0x00: CONTROL    [R/W]   - Core Enable, Global IRQ Enable, Auto-STOP
Offset 0x04: STATUS     [RO]    - Busy, TX Empty, RX Valid, ACK Error, Timeout Error, Done
Offset 0x08: CLOCK_DIV  [R/W]   - [15:0] HIGH_COUNT, [31:16] LOW_COUNT
Offset 0x0C: TX_DATA    [R/W]   - [7:0] Transmit Byte (Address or Data)
Offset 0x10: RX_DATA    [RO]    - [7:0] Received Data Byte (Read-on-Clear)
Offset 0x14: COMMAND    [WO]    - [0] START, [1] WRITE, [2] READ, [3] STOP, [4] RESTART
Offset 0x18: TIMEOUT    [R/W]   - [31:0] Clock-Stretching Timeout Threshold
Offset 0x1C: IRQ        [R/W1C] - [2:0] Pending Flags (W1C), [10:8] Interrupt Enables
```

---

## 5. Protocol Timing & AC Specifications

### 5.1 Standard Mode (100 kHz)
- $F_{SCL} = 100\text{ kHz}$ ($T_{SCL} = 10,000\text{ ns}$).
- Minimum SCL LOW duration ($t_{LOW}$): $\ge 4700\text{ ns}$ (Configured: $500\text{ cycles} = 5000\text{ ns}$).
- Minimum SCL HIGH duration ($t_{HIGH}$): $\ge 4000\text{ ns}$ (Configured: $500\text{ cycles} = 5000\text{ ns}$).
- Minimum START hold time ($t_{HD;STA}$): $\ge 4000\text{ ns}$ (Measured: $5000\text{ ns}$).
- Minimum STOP setup time ($t_{SU;STO}$): $\ge 4000\text{ ns}$ (Measured: $5040\text{ ns}$).
- Minimum Bus-Free time ($t_{BUF}$): $\ge 4700\text{ ns}$ (Enforced: $5000\text{ ns}$).

### 5.2 Fast Mode (400 kHz)
- $F_{SCL} = 400\text{ kHz}$ ($T_{SCL} = 2500\text{ ns}$).
- Minimum SCL LOW duration ($t_{LOW}$): $\ge 1300\text{ ns}$ (Configured: $130\text{ cycles} = 1300\text{ ns}$).
- Minimum SCL HIGH duration ($t_{HIGH}$): $\ge 600\text{ ns}$ (Configured: $120\text{ cycles} = 1200\text{ ns}$).
- Minimum Bus-Free time ($t_{BUF}$): $\ge 1300\text{ ns}$ (Enforced: $1300\text{ ns}$).

---

## 6. Implementation Architecture

The design divides functionality into six frozen lower-level RTL modules and one top-level integration module:
1. `i2c_pkg.sv`: Architectural definitions, parameters, and FSM states.
2. `ahb_lite_slave_if.sv`: Bus adapter, address latching, zero-wait-state control.
3. `i2c_registers.sv`: Synchronous registers, side-effect clears, W1C interrupt logic.
4. `i2c_clock_gen.sv`: Dual-counter SCL generator, stretch-wait detection, synchronous abort.
5. `i2c_timeout.sv`: Exact-N stretch counter, single-cycle pulse generation.
6. `i2c_master.sv`: 12-state master protocol controller, shift registers, arbitration, and abort routing.
7. `i2c_master_top.sv`: Top-level structural wrapper with open-drain pads and input synchronizers.

---

## 7. Verification Targets
The design must achieve 100% pass rate on all self-checking regression testbenches:
- **Task A Testbench (`tb_ahb_registers`):** 46/46 checks.
- **Task B Testbench (`tb_i2c_clock_gen`):** 49/49 checks.
- **Task D Unit Testbench (`tb_i2c_timeout`):** 37/37 checks.
- **Tasks C & D Integration Testbench (`tb_i2c_master`):** 93/93 checks.
- **Task E Full-Chip Testbench (`tb_i2c_master_top`):** 68/68 checks.
- **Total Project Requirement:** 293 / 293 verified dynamic checks (0 failures).
