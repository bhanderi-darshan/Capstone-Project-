# Task C Design Notes: I²C Master Controller FSM

**Module Name:** `i2c_master`  
**Source File:** [`rtl/i2c_master.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/rtl/i2c_master.sv)  
**Package File:** [`rtl/i2c_pkg.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/rtl/i2c_pkg.sv)  
**Clock Generator:** [`rtl/i2c_clock_gen.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/rtl/i2c_clock_gen.sv)  
**Slave Model BFM:** [`tb/i2c_slave_model.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/tb/i2c_slave_model.sv)  
**Testbench File:** [`tb/tb_i2c_master.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/tb/tb_i2c_master.sv)  
**Simulation Log:** [`sim/task_c_simulation.log`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/sim/task_c_simulation.log)  
**Waveform Dump:** `sim/tb_i2c_master.vcd`  
**System Clock:** $F_{HCLK} = 100\text{ MHz}$ ($T_{HCLK} = 10.0\text{ ns}$)  

---

## 1. Module Architecture & Top-Level Integration

The `i2c_master` module implements the complete I²C Master Protocol Finite State Machine (FSM). It interfaces with the Task A register bank (`i2c_registers.sv`), instantiates the Task B clock generator (`i2c_clock_gen.sv`), and manages open-drain bidirectionality on SCL and SDA.

```
                      +-------------------------------------------------+
                      |                   i2c_master                    |
                      |                                                 |
   clk (100 MHz) ---->|                                                 |
   rst_n ------------>|                                                 |
                      |   +-----------------------------------------+   |
   cmd_start_i ------>|   |           Master Protocol FSM           |   |---> hw_busy_o
   cmd_write_i ------>|   |                (13 States)              |   |---> hw_tx_empty_o
   cmd_read_i ------->|   +-----------------------------------------+   |---> hw_rx_valid_o
   cmd_stop_i ------->|        |                            |           |---> hw_ack_error_o
   cmd_restart_i ---->|        v                            v           |---> hw_timeout_error_o (tied 0)
   ctrl_enable_i ---->|   +------------+            +---------------+   |---> hw_done_o
   ctrl_auto_stop_i ->|   | Bit Shift  |            | SCL/SDA Drive |   |---> hw_rx_data_o[7:0]
   clk_high_count_i ->|   | Registers  |            |  Multiplexers |   |
   clk_low_count_i -->|   +------------+            +---------------+   |---> scl_drive_low_o
   tx_data_i[7:0] --->|        ^                            |           |---> sda_drive_low_o
                      |        |                            |           |
                      |   +-------------------+             |           |
                      |   |   i2c_clock_gen   |<------------+           |
                      |   |    (Instance)     |                         |
                      |   +-------------------+                         |
   scl_in ----------->|             |                                   |
   sda_in ----------->|             +-----------------------------------+
```

### Module Ports (20 Ports)

| Signal | Direction | Width | Description |
| :--- | :---: | :---: | :--- |
| `clk` | Input | 1 | 100 MHz System clock ($T = 10.0\text{ ns}$). |
| `rst_n` | Input | 1 | Active-low asynchronous assert, synchronous deassert reset. |
| `cmd_start_i` | Input | 1 | Strobe requesting START condition generation. |
| `cmd_write_i` | Input | 1 | Strobe requesting 8-bit byte write transmission. |
| `cmd_read_i` | Input | 1 | Strobe requesting 8-bit byte read reception. |
| `cmd_stop_i` | Input | 1 | Strobe requesting STOP condition generation. |
| `cmd_restart_i` | Input | 1 | Strobe requesting Repeated START generation. |
| `ctrl_enable_i` | Input | 1 | Core enable bit from `CONTROL[0]`. |
| `ctrl_auto_stop_i`| Input | 1 | AUTO_STOP enable bit from `CONTROL[1]`. |
| `clk_high_count_i`| Input | 16 | High timing count from `CLOCK_DIV[15:0]`. |
| `clk_low_count_i` | Input | 16 | Low timing count from `CLOCK_DIV[31:16]`. |
| `tx_data_i` | Input | 8 | Write data byte from `TX_DATA[7:0]`. |
| `hw_busy_o` | Output | 1 | High from START initiation until STOP completes. |
| `hw_tx_empty_o` | Output | 1 | Registered status: 1 = ready for next TX byte, 0 = buffer active. |
| `hw_rx_valid_o` | Output | 1 | 1-cycle strobe indicating valid read data in `hw_rx_data_o`. |
| `hw_ack_error_o` | Output | 1 | 1-cycle strobe indicating slave NACK received during address/write. |
| `hw_timeout_error_o`| Output | 1 | 1-cycle strobe for timeout (tied to `1'b0` for Task C). |
| `hw_done_o` | Output | 1 | 1-cycle strobe indicating phase/command completion. |
| `hw_rx_data_o` | Output | 8 | Captured 8-bit read payload to `RX_DATA[7:0]`. |
| `scl_in` | Input | 1 | Synchronized physical SCL bus input. |
| `sda_in` | Input | 1 | Synchronized physical SDA bus input. |
| `scl_drive_low_o`| Output | 1 | Open-drain pull-down control for SCL (1 = pull LOW, 0 = float HIGH). |
| `sda_drive_low_o`| Output | 1 | Open-drain pull-down control for SDA (1 = pull LOW, 0 = float HIGH). |

---

## 2. Command, Status, and Handshake Semantics

The controller maintains a strict separation between command acceptance, command completion, and overall transaction state:

1. **`cmd_accept`:** A command (`cmd_start_i`, `cmd_write_i`, `cmd_read_i`, `cmd_stop_i`, `cmd_restart_i`) is sampled on `posedge clk`. When accepted, the FSM transitions from `ST_CMD_READY` (or `ST_IDLE`) to the requested execution state.
2. **`hw_busy_o`:** Asserts immediately when `cmd_start_i` is accepted in `ST_IDLE`. It remains continuously asserted throughout the entire transaction (including during `ST_CMD_READY` and `ST_RESTART`) and deasserts only after `ST_STOP` has completed and the bus lines have been released.
3. **`hw_done_o`:** Generates a 1-cycle active-HIGH pulse upon completion of each individual phase:
   - Completion of START framing (`ST_START`).
   - Completion of 8-bit Address + Slave ACK (`ST_ADDR_ACK`).
   - Completion of 8-bit Data Write + Slave ACK (`ST_WRITE_ACK`).
   - Completion of 8-bit Data Read + Master NACK (`ST_READ_ACK`).
   - Completion of Repeated START framing (`ST_RESTART`).
   - Completion of STOP framing (`ST_STOP`).
4. **`hw_tx_empty_o`:** Implemented as a registered status flag:
   - Resets to `1'b1`.
   - Clears to `1'b0` immediately when `cmd_write_i` is accepted.
   - Restores to `1'b1` when the 9th clock cycle (ACK/NACK) finishes, signaling to software that `TX_DATA` is ready for the next byte.
5. **`hw_ack_error_o`:** Asserts a 1-cycle active-HIGH pulse if a slave returns NACK (SDA=1 at midpoint of 9th SCL HIGH) during `ST_ADDR_ACK` or `ST_WRITE_ACK`. When NACK is detected, `hw_done_o` is suppressed, and the controller initiates an automatic abort STOP sequence.

---

## 3. Finite State Machine (FSM) Specification

The controller implements a 13-state synchronous FSM encoded via `i2c_state_t` in [`rtl/i2c_pkg.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/rtl/i2c_pkg.sv):

```
                        +---------------+
                        |    ST_IDLE    |<--------------------------------------+
                        +---------------+                                       |
                                | cmd_start && bus_is_free                      |
                                v                                               |
                        +---------------+                                       |
                        |   ST_START    |                                       |
                        +---------------+                                       |
                                | Framing done                                  |
                                v                                               |
        +-------------->+---------------+                                       |
        |               | ST_CMD_READY  |----+                                  |
        |               +---------------+    |                                  |
        |                 |           |      |                                  |
        |   cmd_write     |           |      | cmd_read                         |
        |  (Address=1)    |           |      |                                  |
        |                 v           |      v                                  |
        |         +-------------+     |  +-------------+                        |
        |         |   ST_ADDR   |     |  |   ST_READ   |                        |
        |         +-------------+     |  +-------------+                        |
        |                 |           |      |                                  |
        |                 v           |      v                                  |
        |         +-------------+     |  +-------------+                        |
        |         | ST_ADDR_ACK |     |  | ST_READ_ACK |                        |
        |         +-------------+     |  +-------------+                        |
        |            |       |        |      |                                  |
        |        ACK |       | NACK   |      | AUTO_STOP                        |
        +------------+       |        |      |                                  |
                             |        |      v                                  |
                 cmd_write   |        |  +-------------+                        |
                (Address=0)  |        |  |   ST_STOP   |                        |
                             |        |  +-------------+                        |
                             v        |      ^                                  |
                      +-------------+ |      |                                  |
                      |  ST_WRITE   | |      | NACK Abort /                     |
                      +-------------+ |      | cmd_stop                         |
                             |        |      |                                  |
                             v        |      |                                  |
                      +-------------+ |      |                                  |
                      | ST_WRITE_ACK|-+------+                                  |
                      +-------------+        |                                  |
                             |               |                                  |
                             +---------------+                                  |
                             |                                                  |
                             v                                                  |
                      +-------------+                                           |
                      | ST_RESTART  |-------------------------------------------+
                      +-------------+
```

### Detailed State Operations

1. **`ST_IDLE` (`5'd0`):**
   - Bus is quiescent. `scl_drive_low_o = 0`, `sda_drive_low_o = 0`, `hw_busy_o = 0`, `hw_tx_empty_o = 1`.
   - **Bus-Free Qualification:** A free-counter monitors `scl_in` and `sda_in`. Both lines must be observed continuously HIGH for at least $t_{BUF} = \text{low\_count}$ cycles before `bus_is_free` asserts.
   - If `cmd_start_i` arrives when the bus is NOT free (`scl_in == 0` or `sda_in == 0`), the request is rejected without pulling either bus line or pulsing `hw_ack_error_o`.
   - When `cmd_start_i && bus_is_free`, `hw_busy_o <= 1`, pulls SDA LOW, initializes timing counter, and enters `ST_START`.

2. **`ST_START` (`5'd1`):**
   - **Phase 0:** SDA pulled LOW, SCL held HIGH for $t_{HD;STA} = \text{high\_count}$ cycles ($5.0\,\mu\text{s}$ at 100 kHz).
   - **Phase 1:** Pulls SCL LOW for $t_{LOW\_HOLD} = \text{low\_count}$ cycles.
   - Upon completion, pulses `hw_done_o <= 1`, sets `is_addr_phase_q <= 1`, and enters `ST_CMD_READY`.

3. **`ST_CMD_READY` (`5'd12`):**
   - Dedicated intermediate transaction state.
   - SCL is clamped LOW (`fsm_scl_drive_low <= 1`), SDA is released (`fsm_sda_drive_low <= 0`).
   - `hw_busy_o` remains 1; `hw_tx_empty_o` remains 1.
   - Awaits next command from software:
     - `cmd_write_i` with `is_addr_phase_q == 1` $\to$ loads `tx_shift_reg_q`, sets MSB on SDA, enters `ST_ADDR`.
     - `cmd_write_i` with `is_addr_phase_q == 0` $\to$ loads `tx_shift_reg_q`, sets MSB on SDA, enters `ST_WRITE`.
     - `cmd_read_i` $\to$ enters `ST_READ`.
     - `cmd_restart_i` $\to$ enters `ST_RESTART`.
     - `cmd_stop_i` $\to$ enters `ST_STOP`.

4. **`ST_ADDR` (`5'd2`):**
   - Serializes 8-bit Address + R/W bit (MSB first) onto SDA.
   - SCL ownership transferred to `i2c_clock_gen`.
   - On each `cg_cycle_done` pulse, decrements bit counter and shifts next bit onto SDA.
   - After bit 0 completes, releases SDA for slave ACK and transitions to `ST_ADDR_ACK`.

5. **`ST_ADDR_ACK` (`5'd3`):**
   - 9th SCL clock cycle for slave ACK/NACK.
   - Master releases SDA (`sda_owner_byte_q <= 0`).
   - Samples `sda_in` at the exact midpoint of SCL HIGH (`sample_mid_strobe`).
   - On `cg_cycle_done`:
     - SCL ownership safely reclaimed by FSM (`scl_owner_cg_q <= 0`, `fsm_scl_drive_low <= 1`).
     - `hw_tx_empty_o <= 1`.
     - If NACK (`nack_detected_q == 1`): asserts `hw_ack_error_o <= 1`, suppresses `hw_done_o`, and transitions to `ST_STOP` (abort sequence).
     - If ACK (`nack_detected_q == 0`): asserts `hw_done_o <= 1`, strictly IGNORES `ctrl_auto_stop_i`, and transitions to `ST_CMD_READY`.

6. **`ST_WRITE` (`5'd4`):**
   - Serializes 8-bit data payload (MSB first) onto SDA using `i2c_clock_gen`.
   - Operates identically to `ST_ADDR` for bits 7 downto 0.
   - After bit 0 completes, releases SDA and transitions to `ST_WRITE_ACK`.

7. **`ST_WRITE_ACK` (`5'd5`):**
   - 9th SCL clock cycle for slave ACK/NACK on data byte.
   - Samples `sda_in` at SCL HIGH midpoint.
   - On `cg_cycle_done`:
     - Reclaims SCL ownership into FSM clamping.
     - `hw_tx_empty_o <= 1`.
     - If NACK: asserts `hw_ack_error_o <= 1`, suppresses `hw_done_o`, transitions to `ST_STOP`.
     - If ACK: asserts `hw_done_o <= 1`. If `ctrl_auto_stop_i == 1`, transitions to `ST_STOP`; otherwise transitions to `ST_CMD_READY`.

8. **`ST_READ` (`5'd6`):**
   - Receives 8-bit data payload from slave (MSB first).
   - Master floats SDA (`sda_owner_byte_q <= 0`).
   - SCL generated by `i2c_clock_gen`.
   - On each SCL HIGH midpoint strobe (`sample_mid_strobe`), samples `sda_in` into `rx_shift_reg_q`.
   - After 8 bits captured, transitions to `ST_READ_ACK`.

9. **`ST_READ_ACK` (`5'd7`):**
   - 9th SCL clock cycle for Master ACK/NACK.
   - For single-byte read operation (Task C specification), master drives NACK by releasing SDA HIGH (`byte_sda_drive_low <= 0`).
   - On `cg_cycle_done`:
     - Asserts `hw_rx_valid_o <= 1` and updates `hw_rx_data_o <= rx_shift_reg_q`.
     - Asserts `hw_done_o <= 1`.
     - If `ctrl_auto_stop_i == 1`, transitions to `ST_STOP`; otherwise transitions to `ST_CMD_READY`.

10. **`ST_RESTART` (`5'd8`):**
    - Generates Repeated START framing without releasing the bus:
      - **Phase 0:** SCL held LOW, SDA released for $t_{LOW\_HOLD} = \text{low\_count}$ cycles.
      - **Phase 1:** SCL released; waits for physical `scl_in == 1` (supporting clock stretching), then waits $t_{SU;STA} = \text{high\_count}$ cycles ($5.0\,\mu\text{s}$).
      - **Phase 2:** Pulls SDA LOW while SCL is HIGH; waits $t_{HD;STA} = \text{high\_count}$ cycles ($5.0\,\mu\text{s}$).
      - **Phase 3:** Pulls SCL LOW; waits $t_{LOW\_HOLD} = \text{low\_count}$ cycles.
    - Asserts `hw_done_o <= 1`, sets `is_addr_phase_q <= 1`, and enters `ST_CMD_READY`. `hw_busy_o` remains continuously asserted throughout.

11. **`ST_STOP` (`5'd9`):**
    - Generates STOP framing:
      - **Phase 0:** SCL held LOW, SDA pulled LOW for $t_{LOW\_HOLD} = \text{low\_count}$ cycles.
      - **Phase 1:** SCL released; waits for `scl_in == 1`, then waits $t_{SU;STO} = \text{high\_count}$ cycles ($5.0\,\mu\text{s}$).
      - **Phase 2:** SDA released (creating the rising edge on SDA while SCL is HIGH); waits $t_{BUF} = \text{low\_count}$ cycles before completing.
    - Enters `ST_DONE`.

12. **`ST_DONE` (`5'd10`):**
    - Quiescent terminal state.
    - If `abort_active_q == 0`, asserts `hw_done_o <= 1` (suppressed on NACK abort).
    - Releases all internal drive signals (`fsm_scl_drive_low <= 0`, `fsm_sda_drive_low <= 0`).
    - Deasserts `hw_busy_o <= 0` and returns to `ST_IDLE`.

13. **`ST_ERROR` (`5'd11`):**
    - Reserved for hardware fault containment and timeout recovery.

---

## 4. Glitchless SCL Handover Mechanism

One of the most critical aspects of I²C controller design is the handover of SCL ownership between the Master Protocol FSM (framing control) and the hardware clock generator (byte transmission).

### Drive Multiplexing Logic

```systemverilog
assign scl_drive_low_o = fsm_scl_drive_low | (scl_owner_cg_q & cg_scl_drive_low);
assign sda_drive_low_o = fsm_sda_drive_low | (sda_owner_byte_q & byte_sda_drive_low);
```

### Handover Sequence: `ST_CMD_READY` $\to$ Byte Transmission (`ST_ADDR`/`ST_WRITE`/`ST_READ`)

1. In `ST_CMD_READY`, SCL is held LOW by the FSM (`fsm_scl_drive_low = 1`, `scl_owner_cg_q = 0`).
2. When a command arrives, `cg_start_cycle_q` is pulsed to request clock generation, `scl_owner_cg_q` is set to 1, and the FSM maintains `fsm_scl_drive_low = 1`.
3. In the first cycle of `ST_ADDR`, `i2c_clock_gen` is still in IDLE and has not yet asserted its pull-down. `fsm_scl_drive_low` remains asserted, ensuring SCL is never released prematurely.
4. When `i2c_clock_gen` asserts `cg_scl_drive_low = 1`, the Master FSM detects that the clock generator has taken firm control:
   ```systemverilog
   if (cg_scl_drive_low) fsm_scl_drive_low <= 1'b0;
   ```
5. `fsm_scl_drive_low` transitions from `1` to `0` while `cg_scl_drive_low` is already steady at `1`. Because the two signals transition on separate clock edges with positive overlap, **no delta-cycle or analog glitch can occur**.

### Handover Sequence: 9th SCL Cycle (ACK) $\to$ `ST_CMD_READY` / `ST_STOP`

1. During the 9th clock cycle (`ST_ADDR_ACK` / `ST_WRITE_ACK`), `scl_owner_cg_q = 1`.
2. When `cg_cycle_done` asserts, `i2c_clock_gen` has completed the cycle and has ALREADY pulled SCL LOW into its IDLE state (`cg_scl_drive_low = 1`).
3. On this exact cycle, the FSM sets `fsm_scl_drive_low <= 1` and `scl_owner_cg_q <= 0`.
4. Control passes seamlessly back to the FSM while the physical line remains continuously held LOW.

---

## 5. Framing Timing Calculations & I²C Specification Compliance

Timing parameters are derived directly from `clk_high_count_i` and `clk_low_count_i` ($F_{HCLK} = 100\text{ MHz} \implies T = 10.0\text{ ns}$):

| Parameter | Description | Standard Mode Spec ($\le 100\text{ kHz}$) | Target (100 kHz) | Fast Mode Spec ($\le 400\text{ kHz}$) | Target (400 kHz) | Formula |
| :--- | :--- | :---: | :---: | :---: | :---: | :--- |
| $t_{LOW}$ | SCL Clock LOW Period | $\ge 4.7\,\mu\text{s}$ | $5.00\,\mu\text{s}$ ($500\text{ cyc}$) | $\ge 1.3\,\mu\text{s}$ | $1.30\,\mu\text{s}$ ($130\text{ cyc}$) | $\text{low\_count} \times 10\text{ ns}$ |
| $t_{HIGH}$ | SCL Clock HIGH Period | $\ge 4.0\,\mu\text{s}$ | $5.00\,\mu\text{s}$ ($500\text{ cyc}$) | $\ge 0.6\,\mu\text{s}$ | $1.20\,\mu\text{s}$ ($120\text{ cyc}$) | $\text{high\_count} \times 10\text{ ns}$ |
| $t_{HD;STA}$ | Hold Time (Repeated) START | $\ge 4.0\,\mu\text{s}$ | $5.00\,\mu\text{s}$ ($500\text{ cyc}$) | $\ge 0.6\,\mu\text{s}$ | $1.20\,\mu\text{s}$ ($120\text{ cyc}$) | $\text{high\_count} \times 10\text{ ns}$ |
| $t_{SU;STA}$ | Setup Time Repeated START | $\ge 4.7\,\mu\text{s}$ | $5.00\,\mu\text{s}$ ($500\text{ cyc}$) | $\ge 0.6\,\mu\text{s}$ | $1.20\,\mu\text{s}$ ($120\text{ cyc}$) | $\text{high\_count} \times 10\text{ ns}$ |
| $t_{SU;STO}$ | Setup Time for STOP | $\ge 4.0\,\mu\text{s}$ | $5.00\,\mu\text{s}$ ($500\text{ cyc}$) | $\ge 0.6\,\mu\text{s}$ | $1.20\,\mu\text{s}$ ($120\text{ cyc}$) | $\text{high\_count} \times 10\text{ ns}$ |
| $t_{BUF}$ | Bus-Free Time Between STOP & START | $\ge 4.7\,\mu\text{s}$ | $5.00\,\mu\text{s}$ ($500\text{ cyc}$) | $\ge 1.3\,\mu\text{s}$ | $1.30\,\mu\text{s}$ ($130\text{ cyc}$) | $\text{low\_count} \times 10\text{ ns}$ |
| $t_{SAMPLE}$ | Midpoint Sampling Strobe | Center of SCL HIGH | $2.50\,\mu\text{s}$ ($250\text{ cyc}$) | Center of SCL HIGH | $0.60\,\mu\text{s}$ ($60\text{ cyc}$) | $\text{high\_count} / 2 \times 10\text{ ns}$ |

All measured timing parameters strictly satisfy the Philips / NXP I²C-bus specification for both Standard Mode and Fast Mode.

---

## 6. Verification Results (62/62 Tests Passed)

The complete verification suite [`tb/tb_i2c_master.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/tb/tb_i2c_master.sv) was compiled and executed using Icarus Verilog (`iverilog -g2012` and `vvp`).

```text
============================================================================
Task C Verification Results: 62 Passed, 0 Failed out of 62 Tests
============================================================================
>>> ALL TASK C VERIFICATION TESTS PASSED SUCCESSFULLY! <<<
```

### Comprehensive Verification Summary Table

| Test Suite | Test # | Verification Scenario | Expected Result | Measured Result | Status |
| :--- | :---: | :--- | :--- | :--- | :---: |
| **1. Reset & Idle** | 1–6 | Reset state of lines and status flags | `busy=0`, `tx_empty=1`, bus floats HIGH | All outputs quiescent, lines float | **PASS** |
| **2. Bus-Busy Rejection** | 7–10 | `cmd_start_i` issued when SDA held LOW externally | Request rejected, `busy=0`, no bus drive, no ACK error | No lines pulled, `busy=0` | **PASS** |
| **3. START Framing** | 11–15 | START framing and hold time $t_{HD;STA}$ (100 kHz) | $t_{HD;STA} \ge 4000\text{ ns}$, `busy=1`, SCL held LOW in `ST_CMD_READY` | $t_{HD;STA} = 5000\text{ ns}$, SCL held LOW | **PASS** |
| **4. Address Transmission** | 16–22 | Transmit slave address 0x50 + Write (0xA0) with ACK | Slave receives 0x50/W, `tx_empty` drops & restores, `busy=1` | Slave matches 0x50/W, `tx_empty` restores | **PASS** |
| **5. Single Write & STOP** | 23–30 | Write 0xA5, Slave ACK, manual STOP, measure $t_{SU;STO}$ | Slave captures 0xA5, $t_{SU;STO} \ge 4000\text{ ns}$, bus released | Data matches 0xA5, $t_{SU;STO} = 5020\text{ ns}$ | **PASS** |
| **6. Address NACK Abort** | 31–35 | Slave NACKs address; verify automatic abort | `hw_ack_error=1`, `hw_done=0`, automatic STOP, bus released | 1-cycle ACK error pulse, bus released | **PASS** |
| **7. Data NACK Abort** | 36–39 | Slave NACKs data byte; verify automatic abort | `hw_ack_error=1`, `hw_done=0`, automatic STOP, bus released | 1-cycle ACK error pulse, bus released | **PASS** |
| **8. Read & AUTO_STOP** | 40–44 | Read byte 0x3C, Master NACK, verify AUTO_STOP | AUTO_STOP ignored on address; `rx_data=0x3C`, auto STOP | `rx_data = 0x3C`, master returns to IDLE | **PASS** |
| **9. Repeated START** | 45–50 | Write phase (0x11), Repeated START, Read phase (0x77) | `busy` continuously 1, slave sees restart, read captures 0x77 | Seamless multi-phase transfer, 0x77 read | **PASS** |
| **10. Multi-Byte Write** | 51–54 | Burst write: 0x10, 0x20, 0x30 in one transaction | Slave captures all 3 bytes sequentially with SCL held LOW | All 3 bytes confirmed by slave model | **PASS** |
| **11. Clock Stretching** | 55–56 | Slave stretches SCL LOW for $5.0\,\mu\text{s}$ during write | FSM pauses, tolerates stretch, completes write (0x5A) | 0x5A written cleanly after $5.0\,\mu\text{s}$ stretch | **PASS** |
| **12. Fast Mode (400 kHz)** | 57–61 | Timing verification at 400 kHz ($t_{HIGH}=1200\text{ ns}$, $t_{LOW}=1300\text{ ns}$) | $t_{HIGH} \ge 600\text{ ns}$, $t_{LOW} \ge 1300\text{ ns}$, clean STOP | $t_{HIGH} = 1220\text{ ns}$, $t_{LOW} = 1320\text{ ns}$ | **PASS** |
| **13. Glitch Check** | 62 | Continuous glitch monitor across all test transactions | Zero SCL handover glitches ($< 30\text{ ns}$) observed | **0 glitches observed** | **PASS** |
