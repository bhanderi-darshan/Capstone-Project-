# Task B Design Notes: Programmable I²C Clock Generator

**Module Name:** `i2c_clock_gen`  
**Source File:** [`rtl/i2c_clock_gen.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/rtl/i2c_clock_gen.sv)  
**Testbench File:** [`tb/tb_i2c_clock_gen.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/tb/tb_i2c_clock_gen.sv)  
**Simulation Log:** [`sim/task_b_simulation.log`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/sim/task_b_simulation.log)  
**Waveform Dump:** `sim/tb_i2c_clock_gen.vcd`  
**System Clock:** $F_{HCLK} = 100\text{ MHz}$ ($T_{HCLK} = 10.0\text{ ns}$)  

---

## 1. Module Architecture & Top-Level Integration Contract

The `i2c_clock_gen` module is a programmable, hardware-timing engine designed to generate single controlled I²C clock cycles on request from the I²C Master Protocol FSM.

```
                      +------------------------------------------+
                      |             i2c_clock_gen                |
                      |                                          |
   clk (100 MHz) ---->|                                          |
   reset_n ---------->|                                          |---> scl_drive_low
   start_cycle ------>|   +----------------------------------+   |---> busy
   high_count[15:0] ->|   |       5-State Timing FSM         |   |---> cycle_done
   low_count[15:0] -->|   +----------------------------------+   |---> stretch_wait
   scl_in ----------->|                                          |
                      +------------------------------------------+
                                          |
                                          | Open-Drain Bus
                                          v
                              scl_physical = (scl_drive_low || slave_pull_down) ? 0 : 1
```

### Signal Descriptions (10 Ports)

| Signal | Direction | Width | Description |
| :--- | :---: | :---: | :--- |
| `clk` | Input | 1 | 100 MHz System clock ($T = 10\text{ ns}$). |
| `reset_n` | Input | 1 | Active-low asynchronous assert, synchronous deassert reset. |
| `start_cycle` | Input | 1 | 1-cycle active HIGH strobe requesting a single SCL cycle. |
| `high_count` | Input | 16 | Requested SCL HIGH duration in HCLK clock periods. |
| `low_count` | Input | 16 | Requested SCL LOW duration in HCLK clock periods. |
| `scl_in` | Input | 1 | Synchronized physical SCL bus line input. |
| `scl_drive_low` | Output | 1 | Active-HIGH pull-down control: `1` = pull SCL LOW, `0` = float/release. |
| `busy` | Output | 1 | High while a clock generation sequence is in progress. |
| `cycle_done` | Output | 1 | 1-clock-cycle active HIGH pulse signaling completion. |
| `stretch_wait` | Output | 1 | High when master released SCL but physical SCL remains held LOW. |

---

## 2. Finite State Machine (FSM) Specification

The module implements a 5-state synchronous FSM:

1. **`STATE_IDLE` (`3'b000`):**
   - The generator is quiescent. `busy = 0`, `cycle_done = 0`, `stretch_wait = 0`.
   - `scl_drive_low` holds its previous value: `0` at initial reset, or `1` following a completed cycle (holding SCL LOW between data bits).
   - When `start_cycle == 1'b1`: latches clamped counts (`eff_low_count_q`, `eff_high_count_q`), resets counter to 1, asserts `busy <= 1`, asserts `scl_drive_low <= 1`, and transitions to `STATE_SCL_LOW`.

2. **`STATE_SCL_LOW` (`3'b001`):**
   - `busy = 1`, `scl_drive_low = 1`, `cycle_done = 0`, `stretch_wait = 0`.
   - The 16-bit counter increments on each rising clock edge.
   - When `count_q == eff_low_count_q`: the LOW period is complete. The generator releases SCL (`scl_drive_low <= 0`), resets counter to 1, and transitions to `STATE_WAIT_SCL_HIGH`.

3. **`STATE_WAIT_SCL_HIGH` (`3'b010`):**
   - `busy = 1`, `scl_drive_low = 0` (released), `cycle_done = 0`.
   - Physical line state is inspected via `scl_in`:
     - If `scl_in == 0`: An external slave is clock-stretching. `stretch_wait <= 1`. The counter remains frozen at 1.
     - If `scl_in == 1`: Physical SCL has risen. `stretch_wait <= 0`.
       - If `eff_high_count_q == 1`: The 1-cycle HIGH requirement was already satisfied across the transition edge. SCL is pulled LOW (`scl_drive_low <= 1`), `cycle_done <= 1` is pulsed, and state moves to `STATE_CYCLE_DONE`.
       - If `eff_high_count_q > 1`: Counter advances to 2, and state moves to `STATE_SCL_HIGH`.

4. **`STATE_SCL_HIGH` (`3'b011`):**
   - `busy = 1`, `scl_drive_low = 0`, `cycle_done = 0`, `stretch_wait = 0`.
   - Counter increments on each rising edge up to `eff_high_count_q`.
   - When `count_q == eff_high_count_q`: HIGH duration is complete. The generator pulls SCL LOW (`scl_drive_low <= 1`), asserts `cycle_done <= 1`, and transitions to `STATE_CYCLE_DONE`.

5. **`STATE_CYCLE_DONE` (`3'b100`):**
   - 1-clock-cycle handshake state.
   - `busy = 0`, `scl_drive_low = 1` (retains SCL LOW in IDLE), `cycle_done = 0`, `stretch_wait = 0`.
   - Unconditionally transitions back to `STATE_IDLE`.

---

## 3. Timing Calculations & I²C Compliance

With system clock $F_{HCLK} = 100\text{ MHz} \implies T_{HCLK} = 10.0\text{ ns}$:

$$\text{LOW\_TIME} = \text{LOW\_COUNT} \times 10\text{ ns}$$
$$\text{HIGH\_TIME} = \text{HIGH\_COUNT} \times 10\text{ ns}$$
$$\text{SCL\_PERIOD} = \text{LOW\_TIME} + \text{HIGH\_TIME}$$
$$F_{SCL} = \frac{1}{\text{SCL\_PERIOD}}$$

### A. 100 kHz Standard Mode Example
* `LOW_COUNT  = 16'd500` $\implies t_{LOW}  = 500 \times 10\text{ ns} = 5.0\,\mu\text{s}$ (I²C Spec requires $\ge 4.7\,\mu\text{s}$).
* `HIGH_COUNT = 16'd500` $\implies t_{HIGH} = 500 \times 10\text{ ns} = 5.0\,\mu\text{s}$ (I²C Spec requires $\ge 4.0\,\mu\text{s}$).
* Total period = $10.0\,\mu\text{s} \implies 100.00\text{ kHz}$.

### B. 400 kHz Fast Mode Example
* Fast Mode requires an asymmetric duty cycle:
  - Spec requirement: $t_{LOW} \ge 1.3\,\mu\text{s} = 130\text{ HCLK cycles}$.
  - Spec requirement: $t_{HIGH} \ge 0.6\,\mu\text{s} = 60\text{ HCLK cycles}$.
* `LOW_COUNT  = 16'd130` $\implies t_{LOW}  = 130 \times 10\text{ ns} = 1.30\,\mu\text{s}$.
* `HIGH_COUNT = 16'd120` $\implies t_{HIGH} = 120 \times 10\text{ ns} = 1.20\,\mu\text{s}$.
* Total period = $2.50\,\mu\text{s} \implies 400.00\text{ kHz}$.

---

## 4. Hardware Clock-Stretching & Zero-Count Handling

### A. Clock Stretching
* The controller never assumes that releasing SCL implies the physical bus has risen.
* When the master enters `STATE_WAIT_SCL_HIGH`, `scl_drive_low = 0`.
* If a slave holds SCL LOW, `scl_in` is observed as `0`. The FSM asserts `stretch_wait = 1` and freezes the timing counter.
* Only after the slave releases SCL and `scl_in` transitions to `1` does the HIGH period counter begin.
* The actual duration of the SCL HIGH phase post-stretch is guaranteed to equal `high_count` cycles exactly.

### B. Zero-Count Hardware Clamping
* If software programs `LOW_COUNT = 0` or `HIGH_COUNT = 0`:
  - An unchecked subtraction `count - 1` would underflow to `16'hFFFF` (65,535 cycles = $655\,\mu\text{s}$), causing deadlock.
  - The hardware implements zero-count clamping:
    ```systemverilog
    wire [15:0] clamped_low  = (low_count  == 16'd0) ? 16'd1 : low_count;
    wire [15:0] clamped_high = (high_count == 16'd0) ? 16'd1 : high_count;
    ```
  - Both phases are guaranteed to last at least 1 HCLK clock cycle ($10\text{ ns}$), eliminating underflow and glitching.

---

## 5. Verification Results

All 14 test cases in [`tb/tb_i2c_clock_gen.sv`](file:///c:/Users/ASUS/OneDrive/Documents/sem%208/CP/17-11-2026/tb/tb_i2c_clock_gen.sv) were executed with Icarus Verilog:

```text
==================================================================
                      TASK B TEST SUMMARY                         
==================================================================
  TOTAL TESTS : 38
  PASSED      : 38
  FAILED      : 0
==================================================================
  >>> ALL TASK B TESTS PASSED SUCCESSFULLY! <<<
==================================================================
```

| Test Case | Scenario Description | Expected | Measured | Status |
| :--- | :--- | :---: | :---: | :---: |
| **TC01** | Reset state validation | `scl_drive_low=0`, `busy=0`, `done=0`, `stretch=0` | All 0 | **PASS** |
| **TC02** | Normal cycle & IDLE hold | `low=20`, `high=20`, `scl_drive_low` held 1 in IDLE | 20 low, 20 high, held 1 | **PASS** |
| **TC03** | 100 kHz Standard Mode | `low=500`, `high=500`, period = 10,000 ns | 500 low, 500 high, 1000 tot | **PASS** |
| **TC04** | 400 kHz Fast Mode | `low=130`, `high=120`, period = 2,500 ns | 130 low, 120 high, 250 tot | **PASS** |
| **TC05** | Asymmetric counts | `low=40`, `high=60` | 40 low, 60 high | **PASS** |
| **TC06** | `cycle_done` pulse width | Exactly 1 HCLK period | 1 cycle (10 ns) | **PASS** |
| **TC07** | IDLE stability | Zero spurious `cycle_done` pulses in IDLE | 0 spurious pulses | **PASS** |
| **TC08** | Short clock stretch | 10 cycles stretch; `stretch_wait = 1` active | 10 cycles flagged | **PASS** |
| **TC09** | Long clock stretch | 200 cycles stretch; continuous `stretch_wait = 1` | 200 cycles held | **PASS** |
| **TC10** | Timing post-stretch | HIGH phase preserved after 50-cycle stretch | Exactly 40 cycles | **PASS** |
| **TC11** | High counter invariant | High counter does NOT advance while SCL is low | 0 advance, no done | **PASS** |
| **TC12** | Busy lockout protection | `start_cycle` pulsed while busy is ignored | Exactly 1 cycle executed | **PASS** |
| **TC13** | Minimum boundary counts | `low=1`, `high=1` | 1 low, 1 high | **PASS** |
| **TC14** | Zero-count clamping | `low=0`, `high=0` clamped to `1`, `1` | Clamped to 1 low, 1 high | **PASS** |
