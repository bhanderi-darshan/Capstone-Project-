# ASIC Implementation & Physical Design Guide

**Project:** Design and Verification of an AHB-Lite Based I²C Master Controller with Programmable Clock Generation and Hardware Clock-Stretching Timeout  
**Author:** Darshan Bhanderi  
**Status:** **ASIC-Ready RTL Architecture** (Physical synthesis & GDSII tapeout planned as a subsequent project milestone)  

---

## 1. ASIC Readiness & Design Rules Compliance

The synthesizable RTL has been written to comply with standard cell ASIC synthesis rules:
- **Clean Synchronous Clocking:** Single clock domain driven by 100 MHz `HCLK` ($T_{clk} = 10.0\text{ ns}$).
- **No Latches:** All sequential logic uses explicit `always_ff @(posedge HCLK or negedge HRESETn)` blocks with comprehensive condition branches.
- **No Internal Tri-States:** The design uses internal active-low driver signals (`scl_drive_low`, `sda_drive_low`) and connects to bidirectional `inout` pads strictly at the chip boundary in `i2c_master_top.sv`.
- **Reset Domain:** Asynchronous active-low reset (`HRESETn`) with synchronized release network recommended at the pad ring.

---

## 2. Pad Ring & Open-Drain Cell Mapping

In an ASIC implementation, the bidirectional `scl_io` and `sda_io` pins map to standard I/O pad cells configured in open-drain mode:
- **Output Driver:** Driven by `scl_drive_low` (or `sda_drive_low`). When active, the output pull-down transistor conducts to GND; when inactive, the output is High-Z.
- **Input Buffer:** Connected directly to the top-level synchronizer flops (`scl_sync_stage1`, `scl_sync`).
- **External Pull-Up:** Physical I²C bus requires external pull-up resistors to the I/O supply voltage (typically 3.3V or 1.8V).

---

## 3. Candidate ASIC Implementation Flows (Under Evaluation)

The following platforms and toolchains are candidate evaluation targets and are marked as possible platforms until officially selected:

1. **Open-Source OpenLane / SkyWater 130nm Flow:**
   - Technology Node: SkyWater 130nm standard cell library (`sky130_fd_sc_hd`).
   - Toolchain: OpenLane (Yosys for synthesis, OpenROAD for place and route, Magic/KLayout for GDSII DRC/LVS).
   - Target Clock: 100 MHz is easily achievable with large positive slack in this node.

2. **Commercial EDA Synthesis Flow (Synopsys / Cadence):**
   - Synthesis: Synopsys Design Compiler (`dc_shell`) or Cadence Genus.
   - Place & Route: Synopsys IC Compiler II or Cadence Innovus.
   - Signoff: PrimeTime (STA) and Mentor Calibre (DRC/LVS).

---

## 4. Synthesis Constraints Template (SDC)

```tcl
# Timing constraints for 100 MHz HCLK
create_clock -name HCLK -period 10.000 [get_ports HCLK]
set_clock_uncertainty 0.200 [get_clocks HCLK]
set_clock_transition 0.100 [get_clocks HCLK]

# Reset input constraint
set_input_delay -clock HCLK -max 2.000 [get_ports HRESETn]

# AHB-Lite bus input/output delays (assume 40% bus budget)
set_input_delay  -clock HCLK -max 4.000 [get_ports {HADDR* HWDATA* HWRITE HSEL HTRANS* HREADY}]
set_output_delay -clock HCLK -max 4.000 [get_ports {HRDATA* HREADYOUT HRESP irq_o}]

# I2C I/O pins (asynchronous to HCLK due to two-flop synchronizer)
set_false_path -from [get_ports {scl_io sda_io}]
set_false_path -to   [get_ports {scl_io sda_io}]
```
