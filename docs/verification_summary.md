# Project Verification Scoreboard & Summary Report

**Project:** Design and Verification of an AHB-Lite Based I²C Master Controller with Programmable Clock Generation and Hardware Clock-Stretching Timeout  
**Author:** Darshan Bhanderi  
**Simulator:** Icarus Verilog 12.0 / IEEE 1800-2012 SystemVerilog  
**Status:** **100% Passed (293 / 293 Verified Dynamic Checks, 0 Failures)**  

---

## 1. Master Verification Scoreboard

The design was subjected to five distinct verification suites evaluating unit-level behavior, core FSM integration, and full-chip AHB-Lite top-level execution.

| Suite ID | Target Verification Domain | RTL Modules Covered | Testbench Path | Live Log Reference | Checks Executed | Passed | Failed | Status |
|:---:|:---|:---|:---|:---|:---:|:---:|:---:|:---:|
| **Task A** | AHB-Lite Slave Protocol & Register Bank | `ahb_lite_slave_if`, `i2c_registers` | [`tb/tb_ahb_registers.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/tb/tb_ahb_registers.sv) | [`sim/task_a_simulation.log`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/sim/task_a_simulation.log) | 46 | 46 | 0 | **PASS** |
| **Task B** | SCL Clock Generator & Synchronization | `i2c_clock_gen` | [`tb/tb_i2c_clock_gen.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/tb/tb_i2c_clock_gen.sv) | [`sim/task_b_simulation.log`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/sim/task_b_simulation.log) | 49 | 49 | 0 | **PASS** |
| **Task D Unit** | Hardware Timeout Counter Engine | `i2c_timeout` | [`tb/tb_i2c_timeout.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/tb/tb_i2c_timeout.sv) | [`sim/task_d_timeout_unit_simulation.log`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/sim/task_d_timeout_unit_simulation.log) | 37 | 37 | 0 | **PASS** |
| **Tasks C & D** | Integrated Master Core & Timeout Aborts | `i2c_master` (with clock_gen & timeout) | [`tb/tb_i2c_master.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/tb/tb_i2c_master.sv) | [`sim/task_d_simulation.log`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/sim/task_d_simulation.log) | 93 | 93 | 0 | **PASS** |
| **Task E Top** | Full-Chip Integration via AHB-Lite Bus | `i2c_master_top` (entire chip) | [`tb/tb_i2c_master_top.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/tb/tb_i2c_master_top.sv) | [`sim/task_e_top_simulation.log`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/sim/task_e_top_simulation.log) | 68 | 68 | 0 | **PASS** |
| **PROJECT TOTAL** | **Complete System Repository** | **All Modules** | **5 Test Suites** | **6 Simulation Logs** | **293** | **293** | **0** | **PASS (100%)** |

*(Supplementary Note: An earlier baseline simulation log for Task C containing 62 checks is preserved under `sim/task_c_simulation.log` as historical engineering evidence. It is subsumed by the 93 checks in `sim/task_d_simulation.log` and is not double-counted in the 293 total).*

---

## 2. Detailed Test Suite Breakdowns

### 2.1 Task A: AHB-Lite Slave & Registers (46 Checks)
- **Reset State Verification (8 checks):** Checked reset values of CONTROL, STATUS, CLOCK_DIV, TX_DATA, RX_DATA, COMMAND, TIMEOUT, and IRQ.
- **Register Write/Masking (5 checks):** Tested bitfield masking on CONTROL and reserved bits.
- **Clock Divider Configuration (3 checks):** Fast Mode programming (400 kHz) and port decoding.
- **TX_DATA Operation (4 checks):** Data byte writing, port propagation, and masking.
- **TIMEOUT Configuration (3 checks):** Limit write, port propagation, and zero-value disabling.
- **COMMAND Strobes (2 checks):** 1-cycle command pulse generation and hang prevention.
- **STATUS Hardware Updates (4 checks):** Latching of BUSY, TX_EMPTY, sticky flags, read-only protection, and clear-on-command.
- **RX_DATA Buffer & Read-on-Clear (3 checks):** Data capture, RX_VALID latching, and automatic clear upon AHB read.
- **IRQ Logic & Masking (4 checks):** Global masking (`INT_ENABLE`), individual enables, and active interrupt propagation.
- **W1C Interrupt Clearing & Precedence (3 checks):** W1C clear, level deassertion, and simultaneous hardware set + software clear precedence.
- **AHB Wait-States & Pipelining (3 checks):** Single-cycle and multi-cycle bus wait states.
- **Back-to-Back Transfers (2 checks):** Pipelined consecutive AHB-Lite transfers without idle dead-cycles.
- **Unmapped Address Isolation (4 checks):** Address 0x30 read/write returns `HRESP = OKAY`, zero read data, and uncorrupted valid registers.

---

### 2.2 Task B: Programmable Clock Generator (49 Checks)
- **Reset Behavior (4 checks):** SCL drive release, busy deassertion, cycle_done inactive, stretch_wait inactive.
- **Normal Cycle Timing (2 checks):** Low/High phase execution, low hold post-cycle.
- **Standard Mode 100 kHz Timing (3 checks):** 500 cycles low (5.0 $\mu\text{s}$), 500 cycles high (5.0 $\mu\text{s}$), 1000 cycles total.
- **Fast Mode 400 kHz Timing (3 checks):** 130 cycles low (1.3 $\mu\text{s}$), 120 cycles high (1.2 $\mu\text{s}$), 250 cycles total.
- **Asymmetric Timing (2 checks):** 40 cycles low, 60 cycles high asymmetric generation.
- **Cycle Done Pulse Quality (2 checks):** Exactly 1 HCLK cycle pulse width; no spurious pulses in IDLE.
- **Clock Stretching Handshake (12 checks):** `stretch_wait` assertion while slave holds SCL low across 10 and 200 cycles; clean recovery.
- **High Counter Invariance (2 checks):** Verified HIGH counter does not advance while SCL is held LOW.
- **Busy Lockout Protection (1 check):** Spurious start requests during active cycle correctly rejected.
- **Boundary & Clamping Behavior (5 checks):** Minimum 1-cycle counts; zero-count hardware clamping ($0 \to 1$).
- **Synchronous Abort Recovery (13 checks):** Active abort clears busy, clears stretch_wait, suppresses cycle_done, releases SCL, restores IDLE, and executes clean cycle post-abort.

---

### 2.3 Task D Unit: Hardware Timeout Counter (37 Checks)
- **Reset State Behavior (4 checks):** `timeout_event = 0`, `stretch_active = 0`, internal counter = 0.
- **Disabled State (3 checks):** `TIMEOUT_LIMIT = 0` disables event generation; counter holds 0.
- **SCL Release Before Timeout (4 checks):** Short stretch increments counter; SCL rising clears counter without event.
- **Master SCL Pull-Down Clear (3 checks):** Master driving SCL low clears counter immediately.
- **Deterministic Exact-N Assertion (8 checks):** For $N = 5$, verified counter advances $1 \to 2 \to 3 \to 4 \to 5$; exactly on 5th cycle, `timeout_event` pulses HIGH for 1 cycle; 6th cycle drops to 0; no re-triggering during continued stretch.
- **Recovery & Second Episode (4 checks):** Subsequent stretch episode properly resets and re-triggers on $N$-th cycle.
- **Asynchronous Reset Robustness (3 checks):** Immediate clearing during active stretch.
- **Edge Hazard Verification (8 checks):** Concurrent SCL rise with threshold edge suppresses spurious timeout.

---

### 2.4 Tasks C & D Integration: Master Controller Core (93 Checks)
- **Reset & Bus Idle (6 checks):** Lines float HIGH, core idle, TX empty.
- **Bus-Busy START Rejection (4 checks):** START rejected when bus occupied (SDA LOW); no spurious SCL drive.
- **START Framing & Hold Time (5 checks):** START completion, $t_{HD;STA} = 5000\text{ ns}$ ($\ge 4000\text{ ns}$ spec).
- **Address Transmission & ACK (7 checks):** Address `0x50` write, slave ACK, SCL held low for data.
- **Data Write with Slave ACK & Manual STOP (8 checks):** Data byte `0xA5`, slave confirmed, STOP completion, $t_{SU;STO} = 5040\text{ ns}$ ($\ge 4000\text{ ns}$ spec).
- **Address & Data NACK Aborts (9 checks):** Forced NACK pulses `hw_ack_error_o`, suppresses `hw_done_o`, auto-aborts to IDLE, releases bus lines.
- **Data Read with Master NACK & AUTO_STOP (5 checks):** 8 bits read, data matches slave `0x3C`, master NACK, AUTO_STOP returns core to IDLE.
- **Repeated START Multi-Phase (6 checks):** Write phase $\to$ Repeated START $\to$ Read phase (`0x77`) $\to$ STOP.
- **Multi-Byte Burst (4 checks):** Consecutive 3-byte write stream without intermediate STOP.
- **Clock Stretching Tolerance (2 checks):** 5.0 $\mu\text{s}$ stretch tolerated; data `0x5A` intact.
- **Fast Mode 400 kHz Timing (5 checks):** SCL HIGH = 1240 ns ($\ge 600\text{ ns}$), SCL LOW = 1320 ns ($\ge 1300\text{ ns}$).
- **SCL Handover Glitch Check (1 check):** Zero spurious glitches across all transactions.
- **Timeout Aborts Across All States (17 checks):** Timeout abort in DATA, START, RESTART, and STOP framing states; lines released; clock generator reset.
- **Register Bank & Interrupt Integration (6 checks):** STATUS error latching, IRQ pending latching, global `irq_o` assertion, W1C clearing.
- **Post-Timeout Clean Recovery (8 checks):** Subsequent new transaction executes and completes with zero hardware reset.

---

### 2.5 Task E: Full-Chip Top-Level Integration (68 Checks)
Executed exclusively through standard AHB-Lite bus cycles driving physical open-drain lines connected to an external I²C slave BFM (`7'h50`):
- **Scenario 1:** Reset values & memory-mapped register accesses (10 checks).
- **Scenario 2:** Bus idle & physical open-drain pull-up verification (3 checks).
- **Scenario 3:** START condition & slave address ACK in write mode (6 checks).
- **Scenario 4:** Data byte write with slave ACK & multi-byte burst (6 checks).
- **Scenario 5:** STOP condition generation and bus release (5 checks).
- **Scenario 6:** Slave address NACK & automatic abort recovery (4 checks).
- **Scenario 7:** Data read with master NACK & Read-on-Clear verification (7 checks).
- **Scenario 8:** Repeated START sequence (Write $\to$ Restart $\to$ Read) (7 checks).
- **Scenario 9:** Hardware clock-stretching tolerance (3 checks).
- **Scenario 10:** Hardware clock-stretching timeout detection (3 checks).
- **Scenario 11:** System interrupt logic & W1C clearing (8 checks).
- **Scenario 12:** Post-timeout recovery and new transaction without reset (6 checks).

---

## 3. Reproduction & Execution Instructions
To reproduce the full 293-check verification on Linux or Windows:

```bash
# Linux / Ubuntu
./sim/run_all_regressions.sh

# Windows
sim\run_all_regressions.bat
```
All simulation runs output zero compilation warnings and exit with code `0`.
