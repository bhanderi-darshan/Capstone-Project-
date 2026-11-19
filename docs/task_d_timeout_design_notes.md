# Task D — Programmable Hardware Clock-Stretching Timeout Design Notes

**Project:** Design and Verification of an AHB-Lite Based I²C Master Controller with Programmable Clock Generation and Hardware Clock-Stretching Timeout  
**Specification:** `Darshan_Project_doc.pdf`  
**Author:** Senior RTL Design & Verification Engineer  
**Date:** November 2026  
**Status:** Implemented & Formally Verified  

---

## 1. Executive Summary & Design Scope

Task D implements the hardware clock-stretching timeout subsystem for the AHB-Lite to I²C Master Controller. In standard I²C operation, slave devices can hold SCL LOW indefinitely to pace transfers (clock stretching). If a slave device hangs, crashes, or suffers a bus fault, an unmonitored master controller will hang permanently, locking the entire serial bus and potentially deadlocking the host system.

To prevent bus deadlock, this design incorporates:
1. **Dedicated Hardware Timeout Module (`rtl/i2c_timeout.sv`):** A standalone, programmable 32-bit counter with deterministic exact-N cycle threshold semantics and a zero-count disable feature.
2. **Synchronous Clock Generator Abort (`rtl/i2c_clock_gen.sv`):** Added synchronous `abort` input to safely break out of `STATE_WAIT_SCL_HIGH`, clear all counters and internal flags (`busy`, `stretch_wait`, `cycle_done`), and restore clean `STATE_IDLE`.
3. **Master FSM Integration & Abort Recovery (`rtl/i2c_master.sv`):** Integrates internal 2-flop synchronizers for SCL and SDA, tracks bus release (`scl_released`), monitors clock stretching across all phases (data, address, ACK, START, Repeated START, and STOP), freezes framing timers during external stretch, executes immediate abort to `ST_IDLE`, and releases all bus line drives.
4. **Register Bank & Interrupt Integration (`rtl/i2c_registers.sv`):** Connects 32-bit `TIMEOUT` register (`0x18`), asserts sticky `STATUS[4]` (`TIMEOUT_ERROR`), latches `IRQ[2]` (`TIMEOUT_PENDING`) with W1C clearing, and gates the global `irq_o` interrupt line.

---

## 2. Hardware Architecture & Signal Interconnect

```
 +-----------------------------------------------------------------------------------+
 |                              i2c_master.sv                                        |
 |                                                                                   |
 |  +-----------------------+              +--------------------------------------+  |
 |  | 2-Stage Synchronizers |              |            i2c_timeout.sv            |  |
 |  | scl_in  -> scl_sync   |              |                                      |  |
 |  | sda_in  -> sda_sync   |              | scl_released  -------------------+   |  |
 |  +-----------------------+              | scl_sync      -----------------+ |   |  |
 |                                         | timeout_limit (from registers) | |   |  |
 |                                         |                                v v   |  |
 |                                         | stretch_active = released & !scl_sync|  |
 |                                         | count_q == limit -> timeout_event    |  |
 |                                         +-------------------|------------------+  |
 |                                                             | (1 HCLK pulse)      |
 |                                    +------------------------+                     |
 |                                    |                                              |
 |                                    v                                              |
 |  +---------------------------------+-------+     +-----------------------------+  |
 |  |            Master FSM                   |     |      i2c_clock_gen.sv       |  |
 |  |                                         |     |                             |  |
 |  | On timeout_event:                       |     | abort = timeout_event       |  |
 |  | - state_q <= ST_IDLE                    |     | On abort:                   |  |
 |  | - hw_busy_o <= 0 (Immediate release)    |     | - state_q <= STATE_IDLE     |  |
 |  | - hw_done_o <= 0 (Suppressed)           |     | - busy <= 0                 |  |
 |  | - SCL / SDA drives released             |     | - stretch_wait <= 0         |  |
 |  | - hw_timeout_error_o <= timeout_event   |     | - scl_drive_low <= 0        |  |
 |  +-----------------------------------------+     +-----------------------------+  |
 +-----------------------------------------------------------------------------------+
```

---

## 3. Subsystem Specifications & Detailed Mechanics

### 3.1 Exact-N Timeout Semantics (`rtl/i2c_timeout.sv`)

- **Qualifying Condition:** Clock stretching is actively qualified whenever:
  $$\text{stretch\_active} = \text{scl\_released} \ \& \ \sim\!\text{scl\_sync}$$
  where `scl_released` signifies that the master is not asserting SCL LOW and the transaction is active (`state_q != ST_IDLE`).
- **Exact-N Threshold Counting:**
  - When `timeout_limit == N` ($N \ge 1$), `count_q` increments on every consecutive qualifying HCLK cycle where `stretch_active` is asserted.
  - On the **$N$-th consecutive qualifying clock sample**, `count_q + 1'b1 == timeout_limit` triggers.
  - On the next active clock edge, `timeout_event` pulses HIGH for **exactly 1 HCLK clock cycle**.
  - `timeout_fired_q` is latched to prevent re-triggering during the same stretch episode.
  - Verified deterministically with $N = 5$: pulses on the 5th consecutive stretch sample.
- **Zero-Disables Feature:**
  - Setting `timeout_limit == 32'd0` completely disables timeout detection.
  - `count_q` is held at `32'd0`, and `timeout_event` is suppressed.
- **Dynamic Episode Reset:**
  - If physical SCL rises HIGH (slave releases stretch) or the master asserts SCL LOW before reaching $N$, `count_q` immediately resets to `32'd0` and `timeout_fired_q` clears.

### 3.2 Clock Generator Abort Handling (`rtl/i2c_clock_gen.sv`)

- Previous implementations could leave `i2c_clock_gen` stalled in `STATE_WAIT_SCL_HIGH` if the bus hung while stretching.
- Task D introduces a dedicated synchronous `abort` input.
- When `abort` is asserted:
  - `state_q` returns to `STATE_IDLE`.
  - `busy` is immediately cleared to `1'b0`.
  - `stretch_wait` is cleared to `1'b0`.
  - `cycle_done` is suppressed (`1'b0`).
  - `scl_drive_low` is deasserted to `1'b0`.
  - Counter `count_q` is reset to `16'd0`.
- Ensures the clock generator is immediately ready for subsequent transactions without requiring an asynchronous hardware reset.

### 3.3 Master Controller Integration & Recovery (`rtl/i2c_master.sv`)

- **Synthesizable 2-Stage Synchronizers:**
  Two cascaded D-flip-flops are instantiated on both `scl_in` and `sda_in` inside `rtl/i2c_master.sv` clocked by `clk` (HCLK). All internal logic, FSM states, clock generator inputs, timeout monitoring, and midpoint sample Strobes use `scl_sync` and `sda_sync`.
- **START Condition Timing Freeze:**
  In `ST_START` Phase 0, if `scl_sync == 1'b0`, `timing_cnt_q` is frozen at `16'd1`. This guarantees that the master will never pull SDA LOW while physical SCL is LOW, strictly preserving I²C START framing rules while allowing the timeout monitor to detect bus-hangs during START setup.
- **Glitch-Free SCL Ownership Handover:**
  To prevent simulation race conditions and physical sub-nanosecond line glitches during handover between FSM SCL clamping and Clock Generator SCL driving, a dedicated 1-cycle overlapping register `handover_overlap_q` holds FSM SCL drive LOW during the first cycle of `ST_ADDR`, `ST_WRITE`, and `ST_READ`. Zero glitches verified across all test suites.
- **Immediate Abort Recovery (No STOP Deadlock):**
  When `timeout_event` fires, physical SCL is already held LOW externally. Attempting to execute a standard STOP framing sequence would cause an immediate deadlock. The controller therefore:
  1. Aborts immediately to `ST_IDLE`.
  2. Deasserts `hw_busy_o <= 1'b0`.
  3. Suppresses `hw_done_o <= 1'b0`.
  4. Releases all SCL and SDA drive enables (`fsm_scl_drive_low <= 0`, `scl_owner_cg_q <= 0`, `fsm_sda_drive_low <= 0`, `sda_owner_byte_q <= 0`).
  5. Clears TX and RX shift registers and resets `tx_empty_q <= 1'b1`.

### 3.4 Register Bank & Interrupt Handling (`rtl/i2c_registers.sv`)

- **TIMEOUT Register (`0x18`):**
  32-bit read/write register storing the timeout cycle threshold. Reset value is initialized to `DEFAULT_TIMEOUT` (`32'd100000`, corresponding to 1 ms at 100 MHz HCLK).
- **STATUS Register (`0x04`):**
  Bit 4 (`STAT_TIMEOUT_ERROR_BIT`) is asserted when `hw_timeout_error_i` pulses. It remains asserted until cleared by writing a new valid command to the `COMMAND` register.
- **IRQ Register (`0x0C`):**
  - Bit 2 (`IRQ_TIMEOUT_PENDING_BIT`) latches HIGH on `hw_timeout_error_i`.
  - Cleared by writing `1` to bit 2 (Write-1-to-Clear / W1C). Hardware assertion has precedence over software clear if simultaneous.
  - Bit 10 (`IRQ_TIMEOUT_ENABLE_BIT`) gates the pending flag to the interrupt output:
    $$\text{irq\_o} = \text{ctrl\_int\_enable} \ \& \ \left( (\text{irq\_done} \ \& \ \text{irq\_done\_en}) \mid (\text{irq\_ack\_err} \ \& \ \text{irq\_ack\_err\_en}) \mid (\text{irq\_to\_err} \ \& \ \text{irq\_to\_err\_en}) \right)$$

---

## 4. Verification & Testbench Implementation

Two comprehensive SystemVerilog testbenches verify the implementation:

### 4.1 Unit Testbench (`tb/tb_i2c_timeout.sv`)
- 29 targeted, deterministic test cases verifying exact-N cycle timing, boundary conditions (N=1, N=2, N=5, N=10), zero-disables behavior, single-pulse event generation, stretch-active qualification, master-clamped suppression, and dynamic reset upon early slave release.
- **Result:** 29 / 29 PASSED.

### 4.2 Integration Testbench (`tb/tb_i2c_master.sv`)
- 19 Test Suites covering all master states, 100 kHz standard mode, 400 kHz fast mode, clock-stretching tolerance, glitch verification, and comprehensive timeout scenarios:
  - **Suite 14:** Timeout during Data Transfer (slave stretches beyond limit on 5th bit). Verifies clock generator abort, busy deassertion, done suppression, and driver release.
  - **Suite 15:** Timeout during Initial START Framing (external SCL held LOW when START begins).
  - **Suite 16:** Timeout during Repeated START Framing (external SCL held LOW during Phase 1 SCL release).
  - **Suite 17:** Timeout during STOP Framing (external SCL held LOW during Phase 1 SCL release).
  - **Suite 18:** Register Bank & Interrupt Integration (STATUS[4], IRQ[2], W1C clearing, CONTROL.INT_ENABLE, and command clearing).
  - **Suite 19:** Clean Transaction Recovery Post-Timeout (issuing a full START-Address-Write-STOP transaction immediately following a timeout abort).
