# Task E — Step 3: Full-Chip Top-Level Verification Report

**Project:** Design and Verification of an AHB-Lite Based I²C Master Controller with Programmable Clock Generation and Hardware Clock-Stretching Timeout  
**Primary Specification:** `Darshan_Project_doc.pdf`  
**Standard:** IEEE 1800-2012 SystemVerilog / ARM AHB-Lite v1.0 / UM10204 I²C-bus Specification  
**Status:** Verification Passed (68/68 Full-Chip Checks, 225/225 Regression Checks, 0 Failures)  
**Date:** November 19, 2026  

---

## 1. Executive Summary

This report documents the full-chip verification of the synthesizable top-level integration module [`rtl/i2c_master_top.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/rtl/i2c_master_top.sv) using the dedicated top-level self-checking testbench [`tb/tb_i2c_master_top.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/tb/tb_i2c_master_top.sv).

All 12 required full-chip verification scenarios were executed exclusively through standard AHB-Lite bus cycles (`HADDR`, `HWDATA`, `HRDATA`, `HWRITE`, `HSEL`, `HTRANS`, `HREADY`, `HREADYOUT`, `HRESP`) driving the physical open-drain I²C bus (`scl_io`, `sda_io`) connected to an external I²C slave Bus Functional Model (`u_slave` at 7-bit address `7'h50`).

### Key Verification Metrics
- **Top-Level Dynamic Verification Checks:** 68 executed, 68 passed, 0 failed (100% pass rate).
- **Frozen RTL Regression Checks:** 225 executed across 4 regression testbenches, 225 passed, 0 failed.
- **Combined Project Verification Checks:** 293 executed, 293 passed, 0 failed.
- **RTL Freeze Status:** All Task A–D RTL files (`i2c_pkg.sv`, `ahb_lite_slave_if.sv`, `i2c_registers.sv`, `i2c_clock_gen.sv`, `i2c_timeout.sv`, `i2c_master.sv`) remained strictly unmodified and byte-frozen.

---

## 2. Testbench Architecture & Environment

The top-level verification harness adheres to ASIC industry verification best practices:

```
+-----------------------------------------------------------------------------------------------+
| tb_i2c_master_top                                                                             |
|                                                                                               |
|  +--------------------+                               +------------------------------------+  |
|  | AHB Master Driver  |                               | i2c_master_top (DUT)               |  |
|  | - ahb_write_reg()  |==== HADDR, HWDATA, HTRANS ===>| - ahb_lite_slave_if (u_ahb_slave)  |  |
|  | - ahb_read_reg()   |<=== HRDATA, HRESP, HREADYOUT =| - i2c_registers (u_registers)      |  |
|  | - wait_bus_free()  |                               | - i2c_master (u_master)            |  |
|  +--------------------+                               +------------------------------------+  |
|                                                                    ||          ||             |
|                                                                  scl_io      sda_io           |
|                                                                    ||          ||             |
|                                             pullup (scl) <=========++==========++===========> |
|                                             pullup (sda) <=========++==========++             |
|                                                                    ||          ||             |
|  +-----------------------------------------------------------------++----------++----------+  |
|  | i2c_slave_model (u_slave, SLAVE_ADDR = 7'h50)                                           |  |
|  | - Open-drain line drives (scl_drive_low, sda_drive_low)                                 |  |
|  | - Programmable ACK/NACK (force_addr_nack, force_data_nack)                              |  |
|  | - Hardware clock stretching (stretch_en, stretch_duration_ns, stretch_on_bit)           |  |
|  | - Data reception, transmission (0xD5, 0x66), and protocol frame monitoring              |  |
|  +-----------------------------------------------------------------------------------------+  |
+-----------------------------------------------------------------------------------------------+
```

### 2.1 AHB-Lite Driver Tasks
The testbench interacts with the DUT solely through AHB-Lite protocol-compliant bus cycles:
- **`ahb_write_reg(addr, data)`**: Drives pipelined Address Phase (`HSEL=1`, `HTRANS=NONSEQ`, `HWRITE=1`, `HADDR=addr`) followed by Data Phase (`HWDATA=data`). Guarantees clean zero-wait-state handshakes with internal register bank.
- **`ahb_read_reg(addr, data)`**: Issues pipelined Read Address Phase (`HSEL=1`, `HTRANS=NONSEQ`, `HWRITE=0`, `HADDR=addr`), and samples `HRDATA` on the terminating clock edge of the Data Phase.
- **`wait_done_or_error(max_cycles, status_out, timed_out)`**: Implements bounded non-intrusive polling of the memory-mapped `STATUS` register (0x04) for `STATUS.DONE` (bit 5), `STATUS.ACK_ERROR` (bit 3), or `STATUS.TIMEOUT_ERROR` (bit 4) with an emergency cycle watchdog guard.
- **`wait_bus_free()`**: Enforces the required $t_{BUF}$ bus-free qualification period (250 HCLK cycles = 2500 ns) between STOP/aborts and subsequent START conditions, satisfying I²C Fast Mode specifications ($t_{BUF} \ge 1.3\ \mu\text{s}$).

### 2.2 Physical Bus Modeling
- **Simulation Pull-Ups:** Declared `pullup (scl);` and `pullup (sda);` to emulate the mandatory external resistor network ($R_p = 2\ \text{k}\Omega\text{ to }4.7\ \text{k}\Omega$).
- **Dual-Master/Slave Open-Drain Integration:** Both `i2c_master_top` and `i2c_slave_model` drive lines low actively (`1'b0`) and float high-impedance (`1'bz`) to allow passive resistor pull-up.

---

## 3. Detailed Verification Results (12 Scenarios)

The testbench systematically verifies all 12 operational scenarios mandated by the project specification:

### Scenario 1: Reset Values & Memory-Mapped Register Accesses (Tests 1–10)
- Verified power-on reset values:
  - `CONTROL` (0x00) = `0x00000000`
  - `STATUS` (0x04) = `0x00000002` (`TX_EMPTY = 1`, core idle)
  - `CLOCK_DIV` (0x08) = `0x01F401F4` (500 cycles LOW / 500 cycles HIGH = 100 kHz)
  - `TIMEOUT` (0x18) = `0x000186A0` (100,000 cycles = 1.0 ms)
  - `IRQ` (0x1C) = `0x00000000`
- Configured 400 kHz Fast Mode timing (`CLOCK_DIV = 0x00820078`: 130 cycles LOW = 1300 ns, 120 cycles HIGH = 1200 ns). Readback verified.
- Verified `TX_DATA` write and readback (`0xA5`).
- Verified robust unmapped address access (0x30): returns 0, returns `HRESP = OKAY` (0), and leaves all valid peripheral registers completely uncorrupted.

### Scenario 2: Bus Idle & Open-Drain Physical Line Verification (Tests 11–13)
- Verified physical `scl` and `sda` float cleanly HIGH via the external pull-up resistors in IDLE state.
- Verified global interrupt output `irq_o` is deasserted (`1'b0`) prior to transaction initiation.

### Scenario 3: START Condition & Slave Address ACK in Write Mode (Tests 14–19)
- Ensured $t_{BUF}$ qualification period elapsed.
- Enabled controller (`CONTROL.ENABLE = 1`) and issued `CMD_START` (0x01).
- Confirmed `STATUS.BUSY` asserted (`1'b1`) via AHB read.
- Verified START framing completed (`STATUS.DONE = 1`) and external slave captured `start_seen = 1`.
- Written slave address `8'hA0` (7-bit `7'h50` + Write bit `0`) to `TX_DATA` and issued `CMD_WRITE`.
- Verified Address phase completed with slave ACK (`STATUS.ACK_ERROR = 0`) and slave captured matching address `7'h50`.

### Scenario 4: Data Byte Write with Slave ACK & Multi-Byte Write (Tests 20–25)
- Transmitted payload data byte `0x3C`. Verified `STATUS.DONE = 1`, `STATUS.ACK_ERROR = 0`, and slave received `0x3C`.
- Transmitted consecutive data byte `0x7E` within the same transaction. Verified multi-byte sequencing without unintended STOP/START framing. Slave confirmed `0x7E`.

### Scenario 5: STOP Condition Generation (Tests 26–30)
- Issued `CMD_STOP` (0x08). Verified completion with `STATUS.DONE = 1`.
- Verified `STATUS.BUSY` deasserted to `1'b0`.
- Verified slave flagged `stop_seen = 1`.
- Verified both physical lines `scl` and `sda` released to float HIGH.

### Scenario 6: Slave Address NACK and Automatic Abort Recovery (Tests 31–34)
- Configured slave model to force NACK on address (`force_addr_nack = 1`).
- Issued START and transmitted address `8'hA0`.
- Verified `STATUS.ACK_ERROR` asserted to `1'b1`.
- Verified `STATUS.DONE` was strictly suppressed on NACK.
- Verified the master FSM automatically triggered the abort STOP sequence, deasserted `STATUS.BUSY` back to `0`, and released both bus lines without software deadlock.

### Scenario 7: Data Read with Master NACK & Read-on-Clear (Tests 35–41)
- Slave configured with return payload byte `0xD5`.
- Issued START and transmitted Read address `8'hA1` (7-bit `7'h50` + Read bit `1`). Address was ACKed.
- Issued `CMD_READ` (0x04).
- Verified read operation completed (`STATUS.DONE = 1`) with master generating NACK on 9th clock cycle.
- Verified `STATUS.RX_VALID` asserted to `1'b1`.
- Read `ADDR_RX_DATA` via AHB-Lite and confirmed received byte matched `8'hD5`.
- Verified Read-on-Clear side-effect: immediate subsequent read of `ADDR_STATUS` confirmed `STATUS.RX_VALID` cleared to `0`.
- Issued `CMD_STOP` to return master to IDLE.

### Scenario 8: Repeated START Sequence (Write -> Restart -> Read) (Tests 42–48)
- Phase 1: Wrote address `8'hA0` and data byte `0x44` to slave. Slave confirmed reception.
- Phase 2: Issued `CMD_RESTART` (0x10) without prior STOP. Verified `STATUS.DONE = 1` and confirmed `STATUS.BUSY` remained continuously asserted `1` throughout framing.
- Phase 3: Issued Read address `8'hA1`, followed by `CMD_READ`. Read back payload `8'h66` from slave.
- Terminated transaction cleanly with `CMD_STOP`.

### Scenario 9: Hardware Clock-Stretching Tolerance (Tests 49–51)
- Configured slave model to stretch SCL LOW for 3.0 $\mu\text{s}$ (300 HCLK cycles) on data bit 3.
- Executed transfer with default timeout (100,000 cycles).
- Master paused clock generation and waited for SCL to release.
- Verified transfer completed successfully (`STATUS.DONE = 1`), with zero timeout error (`STATUS.TIMEOUT_ERROR = 0`), and slave captured payload `0x5A` intact.

### Scenario 10: Hardware Clock-Stretching Timeout Detection (Tests 52–54)
- Programmed short timeout limit: `TIMEOUT = 32'd300` (3.0 $\mu\text{s}$).
- Configured slave to stretch SCL for 500 $\mu\text{s}$ on data bit 2 (exceeding 3.0 $\mu\text{s}$ limit).
- Initiated data transfer. At exactly 300 cycles of stretching, hardware timeout counter fired:
  - Verified `STATUS.TIMEOUT_ERROR` asserted to `1'b1`.
  - Verified `STATUS.BUSY` immediately forced to `0`.
  - Verified `STATUS.DONE` was strictly suppressed.
- Slave stretch released.

### Scenario 11: System Interrupt Logic & W1C Clearing (Tests 55–62)
- Enabled global interrupt (`CONTROL.INT_ENABLE = 1`) and individual enables in `IRQ` (`0x00000700`: `DONE_IE`, `ACK_ERROR_IE`, `TIMEOUT_IE`).
- Verified `irq_o` asserted due to the pending timeout event from Scenario 10 (`IRQ.TIMEOUT_PENDING = 1`).
- Cleared pending flags using Write-1-to-Clear (W1C) write (`0x00000707`). Verified all pending flags cleared to `0` and `irq_o` dropped to `0`.
- Initiated a START command. Upon completion, verified `irq_o` asserted to `1` and `IRQ.DONE_PENDING` asserted.
- Executed W1C write (`0x00000701`). Verified `IRQ.DONE_PENDING` cleared to `0` and `irq_o` deasserted.
- Concluded with STOP and disabled interrupts.

### Scenario 12: Recovery & New Transaction Post-Timeout (Tests 63–68)
- Restored default timeout threshold (`TIMEOUT = 32'd100000`).
- Allowed $t_{BUF}$ to elapse; verified bus lines free (`SCL=1, SDA=1`).
- Executed full end-to-end write transaction (START -> Address `0xA0` -> Data `0x99` -> STOP) without requiring any hardware reset.
- Verified 100% clean recovery: START succeeded, Address ACKed, slave received `0x99`, STOP finished, and bus returned to High-Z.

---

## 4. Test Summary Table

| Scenario | Description | Target Standard / Spec | Checks Executed | Passed | Failed | Result |
|:---:|:---|:---|:---:|:---:|:---:|:---:|
| **1** | Reset Values & AHB Register Access | AHB-Lite v1.0 / Register Map | 10 | 10 | 0 | **PASS** |
| **2** | Bus Idle & Open-Drain Physical Lines | UM10204 Open-Drain Pull-Up | 3 | 3 | 0 | **PASS** |
| **3** | START Framing & Slave Address ACK | I²C Bus Framing / Fast Mode | 6 | 6 | 0 | **PASS** |
| **4** | Data Write with Slave ACK (Multi-Byte) | I²C Write Protocol | 6 | 6 | 0 | **PASS** |
| **5** | STOP Condition Generation | I²C Bus Release | 5 | 5 | 0 | **PASS** |
| **6** | Slave Address NACK & Auto-Abort | Fault Handling & Bus Release | 4 | 4 | 0 | **PASS** |
| **7** | Data Read with Master NACK & Read-on-Clear | I²C Master Read / Registers | 7 | 7 | 0 | **PASS** |
| **8** | Repeated START Sequence | Multi-Phase Restart Protocol | 7 | 7 | 0 | **PASS** |
| **9** | Hardware Clock-Stretching Tolerance | SCL Synchronization | 3 | 3 | 0 | **PASS** |
| **10** | Hardware Clock-Stretching Timeout | Darshan Project Spec Task D | 3 | 3 | 0 | **PASS** |
| **11** | System Interrupt Logic & W1C Clearing | ARM NVIC Compatible IRQ | 8 | 8 | 0 | **PASS** |
| **12** | Recovery & New Transaction Post-Timeout | Resilient System Operation | 6 | 6 | 0 | **PASS** |
| **TOTAL** | **Full-Chip System Verification** | **Complete Project Spec** | **68** | **68** | **0** | **PASS** |

---

## 5. Regression Suite Reconciliation

To ensure no existing features were broken by top-level integration or testbench synchronization adjustments, all four previous verification testbenches were recompiled and rerun:

| Verification Suite | Target RTL Tested | Testbench Path | Checks Executed | Checks Passed | Failures | Status |
|:---|:---|:---|:---:|:---:|:---:|:---:|
| **Task A** | `ahb_lite_slave_if`, `i2c_registers` | [`tb/tb_ahb_registers.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/tb/tb_ahb_registers.sv) | 46 | 46 | 0 | **PASS** |
| **Task B** | `i2c_clock_gen` | [`tb/tb_i2c_clock_gen.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/tb/tb_i2c_clock_gen.sv) | 49 | 49 | 0 | **PASS** |
| **Task D Unit** | `i2c_timeout` | [`tb/tb_i2c_timeout.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/tb/tb_i2c_timeout.sv) | 37 | 37 | 0 | **PASS** |
| **Tasks C & D** | `i2c_master` (integrated core) | [`tb/tb_i2c_master.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/tb/tb_i2c_master.sv) | 93 | 93 | 0 | **PASS** |
| **Task E Top** | `i2c_master_top` (full chip) | [`tb/tb_i2c_master_top.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/tb/tb_i2c_master_top.sv) | 68 | 68 | 0 | **PASS** |
| **GRAND TOTAL** | **Complete System Repository** | **All Verification Suites** | **293** | **293** | **0** | **PASS** |

---

## 6. Simulation Commands & Evidence

### 6.1 Top-Level Full-Chip Simulation Command
```powershell
# Compile full-chip RTL and testbench
.\tools\iverilog\bin\iverilog.exe -g2012 -Wall -o sim\tb_i2c_master_top.vvp `
  rtl\i2c_pkg.sv rtl\ahb_lite_slave_if.sv rtl\i2c_registers.sv rtl\i2c_clock_gen.sv `
  rtl\i2c_timeout.sv rtl\i2c_master.sv rtl\i2c_master_top.sv tb\i2c_slave_model.sv tb\tb_i2c_master_top.sv

# Execute simulation and generate log
.\tools\iverilog\bin\vvp.exe sim\tb_i2c_master_top.vvp | Out-File -Encoding utf8 sim\task_e_top_simulation.log
```

### 6.2 Raw Simulation Log Excerpt
The complete, unabridged simulation output is preserved in [`sim/task_e_top_simulation.log`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/sim/task_e_top_simulation.log):
```text
============================================================================
                      TASK E STEP 3 TEST SUMMARY                            
============================================================================
  TOTAL VERIFICATION CHECKS : 68
  PASSED                    : 68
  FAILED                    : 0
============================================================================
  >>> ALL TASK E FULL-CHIP VERIFICATION CHECKS PASSED SUCCESSFULLY! <<<
============================================================================
```

### 6.3 Waveform Dump Artifacts
The full-chip simulation generated standard Value Change Dump (VCD) trace [`sim/tb_i2c_master_top.vcd`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/sim/tb_i2c_master_top.vcd) containing complete signal transitions for:
- AHB-Lite bus interface signals (`HCLK`, `HRESETn`, `HADDR`, `HWDATA`, `HRDATA`, `HSEL`, `HTRANS`, `HWRITE`, `HREADY`, `HREADYOUT`, `HRESP`).
- Internal peer module interconnects between `u_ahb_slave`, `u_registers`, and `u_master`.
- Physical I²C lines (`scl`, `sda`) with open-drain bidirectional handshakes.
- System interrupt output (`irq_o`).

---

## 7. Conclusion

Task E Step 3 full-chip verification is **100% complete and fully verified**. The integrated AHB-Lite I²C Master Controller with programmable clock generation and hardware clock-stretching timeout satisfies every functional, timing, and architectural requirement defined in `Darshan_Project_doc.pdf` and industry standards.
