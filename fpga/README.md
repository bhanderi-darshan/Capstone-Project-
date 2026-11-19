# FPGA Implementation Guide & Candidate Platform Evaluation

**Project:** Design and Verification of an AHB-Lite Based I²C Master Controller with Programmable Clock Generation and Hardware Clock-Stretching Timeout  
**Author:** Darshan Bhanderi  
**Status:** **RTL Synthesizable & Validated** (Physical FPGA board deployment planned as a subsequent project milestone)  

---

## 1. Architectural Readiness for FPGA Synthesis

The controller RTL is fully synthesizable and vendor-agnostic:
- Strictly synchronous single-clock domain design clocked by 100 MHz `HCLK`.
- Asynchronous reset with active-low polarity (`HRESETn`), synchronized internally where required.
- Two-stage flip-flop synchronizers on physical inputs (`scl_io` and `sda_io`) to prevent meta-stability.
- No internal tri-state buses. Bidirectional signals are confined to the top-level boundary.

---

## 2. External Physical Pin Requirements

The I²C protocol requires open-drain bus lines with pull-up resistors:
- **`scl_io`**: Serial Clock line.
- **`sda_io`**: Serial Data line.

### Mandatory Pull-Up Resistors
FPGA internal weak pull-ups ($10\ \text{k}\Omega\text{ to }100\ \text{k}\Omega$) are generally too weak to satisfy I²C Fast Mode (400 kHz) rise time constraints ($t_r \le 300\text{ ns}$). External pull-up resistors ($2.2\ \text{k}\Omega\text{ to }4.7\ \text{k}\Omega$) connected to the 3.3V VCCIO rail are mandatory on the board's header pins.

---

## 3. Candidate FPGA Platforms (Under Evaluation)

The following platforms are candidate evaluation targets and are marked as possible platforms until officially selected for demonstration:

1. **Xilinx Artix-7 Family (e.g., Basys-3 / Nexys-4):**
   - Toolchain: AMD Xilinx Vivado ML.
   - Clocking: 100 MHz onboard oscillator directly drives `HCLK`.
   - Constraints: Dedicated `.xdc` pin mapping and I/O standard constraints (`LVCMOS33`).

2. **Intel Cyclone IV / Cyclone V Family (e.g., DE10-Lite / DE2-115):**
   - Toolchain: Intel Quartus Prime Lite Edition.
   - Clocking: 50 MHz onboard clock doubled to 100 MHz via an ALTPLL / PLL IP core.
   - Constraints: `.qsf` pin assignments and voltage standards.

---

## 4. Synthesis & Implementation Checklist
When target hardware is finalized:
1. Create a top-level FPGA wrapper mapping AHB-Lite signals to either an on-chip softcore processor (e.g., RISC-V / MicroBlaze) or a UART-to-AHB debug bridge.
2. Assign `scl_io` and `sda_io` to 3.3V tolerant Pmod / GPIO header pins.
3. Apply timing constraint: `create_clock -period 10.000 -name HCLK [get_ports HCLK]`.
4. Validate timing closure with zero setup and hold violations.
