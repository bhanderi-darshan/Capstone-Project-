# GitHub Publication and Repository Reconciliation Report

**Project Title:** Design and Verification of an AHB-Lite Based I²C Master Controller with Programmable Clock Generation and Hardware Clock-Stretching Timeout  
**Author / Maintainer:** Darshan Bhanderi (`bhanderi-darshan` / `dgbhanderi007@gmail.com`)  
**Repository URL:** [https://github.com/bhanderi-darshan/Capstone-Project-.git](https://github.com/bhanderi-darshan/Capstone-Project-.git)  
**Publication Date:** November 19, 2026  
**Document Reference:** `docs/github_publication_report.md`  

---

## 1. Executive Summary

This report documents the formal publication and Git history reconciliation of the **AHB-Lite to I²C Master Controller** Capstone Project repository on GitHub.

Following the approved **Option 1 (Linear History Rebase)** strategy, the complete SystemVerilog RTL, testbench regression suite, comprehensive documentation, and build automation were rebased directly on top of the remote repository's pre-existing commit (`63c3ae6`). A standard non-destructive fast-forward push was executed, strictly avoiding any forced push operations (`--force` / `--force-with-lease`).

All pre-existing Intel Quartus Prime synthesis project files in `fpga/` have been fully preserved, and the six Task A–D RTL modules remain strictly frozen. The full system regression suite verified all **293 dynamic assertions across all five test suites with zero failures**.

---

## 2. Git History & Remote Status

### 2.1 Pre-Publication State
- **Remote Base Commit:** `63c3ae643fcf1d4d3400ea8296bc2452d8a06a03`
- **Remote Commit Author:** `Darshan Bhanderi <dgbhanderi007@gmail.com>`
- **Remote Commit Date:** `Mon Oct 19 23:38:29 2026 +0530`
- **Remote Commit Message:** `version 1`
- **Remote Branch:** `main`
- **Pre-existing Remote Files:** Pre-existing Quartus Prime FPGA project hierarchy (`fpga/*.qpf`, `*.qsf`, `*.qws`, `output_files/`, `simulation/`), placeholder `.gitignore`, and initial `README.md`.

### 2.2 Rebase Execution & Conflict Resolution
- **Pre-rebase Local Backup:** Created branch `backup-master-cf01d20` pointing to local commit `cf01d20`.
- **Rebase Target:** Root-commit rebase onto `origin/main` (`63c3ae6`).
- **Conflict Resolution:**
  1. `.gitignore`: Combined the remote Quartus/ModelSim ignore rule (`fpga/simulation/modelsim/verilog_libs/`) with the comprehensive SystemVerilog simulation and build ignore configuration.
  2. `rtl/i2c_clock_gen.sv`: Resolved conflict in favor of the verified, synthesizable 185-line Task B clock generator module, replacing the legacy 36-line placeholder counter from `63c3ae6`.
  3. `sim/run_all_regressions.bat`: Maintained the complete 5-suite Windows automation batch runner.
- **Resulting Commit Hash:** `bbf017acd00ec710efd8cfbe8db58cbfc73daf37`
- **Commit Authorship:** `bhanderi-darshan <dgbhanderi007@gmail.com>`
- **Commit Date:** `Thu Nov 19 11:22:00 2026 +0530`
- **Commit Message:** `Organize AHB-I2C controller project and update documentation`

### 2.3 Publication Push Confirmation
- **Push Command:** `git push origin main` (Standard Fast-Forward Push; no force flag permitted or used).
- **Remote Refspec Update:** `63c3ae6..bbf017a  main -> main`
- **Push Status:** Successfully published (Exit Code: 0).
- **Working Tree Status:** Clean (`nothing to commit, working tree clean`).
- **Branch Tracking:** Local `main` is up to date with `origin/main`.

```
* bbf017a (HEAD -> main, origin/main) Organize AHB-I2C controller project and update documentation
* 63c3ae6 version 1
```

---

## 3. Repository File & Directory Inventory

The published commit (`bbf017a`) introduces 46 managed files (11,069 insertions, 27 deletions) structured into a clean industry-standard layout:

```
Capstone-Project-/
├── .gitignore                                      # Comprehensive toolchain ignore rules
├── README.md                                       # Master 24-section professional documentation
├── asic/
│   └── README.md                                   # ASIC synthesis & SkyWater 130nm candidate notes
├── docs/
│   ├── architecture.md                             # Detailed block diagrams & datapath design
│   ├── github_publication_report.md                # This publication and reconciliation report
│   ├── project_specification.md                    # Primary requirements & feature specs
│   ├── register_map.md                             # 32-bit register map & bitfield definitions
│   ├── task_b_design_notes.md                      # Clock generator design notes
│   ├── task_c_design_notes.md                      # I2C master core FSM design notes
│   ├── task_d_final_audit.md                       # Comprehensive 8-dimension architecture audit
│   ├── task_d_final_closure.md                     # Verification closure & sign-off report
│   ├── task_d_report_correction_summary.md         # Audit reconciliation summary
│   ├── task_d_timeout_design_notes.md              # Clock-stretching timeout unit notes
│   ├── task_e_step1_rtl_interface_inspection.md    # Pre-integration interface inspection report
│   ├── task_e_step2_final_review.md                # Top-level RTL sign-off review
│   ├── task_e_step2_top_level_integration.md       # Top-level architecture & integration spec
│   ├── task_e_step3_full_chip_verification.md      # Full-chip verification report (68 checks)
│   ├── verification_summary.md                     # Consolidated 293-check verification matrix
│   └── references/
│       ├── darshan_deciphered.txt                  # Extracted project specification transcript
│       └── darshan_extracted.txt                   # Baseline requirements reference
├── fpga/
│   ├── ahb_i2c_controller.qpf                      # Preserved Intel Quartus Prime Project File
│   ├── ahb_i2c_controller.qsf                      # Preserved Quartus Settings & Pin Assignments
│   ├── ahb_i2c_controller.qws                      # Preserved Quartus Workspace File
│   ├── ahb_i2c_controller_nativelink_simulation.rpt# Preserved NativeLink simulation report
│   ├── db/                                         # Preserved Quartus database files
│   ├── incremental_db/                             # Preserved incremental synthesis files
│   ├── output_files/                               # Preserved synthesis reports & bitstreams (.sof)
│   ├── simulation/                                 # Preserved ModelSim simulation setups
│   └── README.md                                   # FPGA implementation guide & board notes
├── rtl/
│   ├── ahb_lite_slave_if.sv                        # Task A: AHB-Lite bus interface adapter [FROZEN]
│   ├── i2c_clock_gen.sv                            # Task B: Programmable clock generator [FROZEN]
│   ├── i2c_master.sv                               # Task C/D: I2C master protocol FSM [FROZEN]
│   ├── i2c_master_top.sv                           # Task E: Top-level integration module
│   ├── i2c_pkg.sv                                  # Task A: Common package & state definitions [FROZEN]
│   ├── i2c_registers.sv                            # Task A: 32-bit memory-mapped register bank [FROZEN]
│   └── i2c_timeout.sv                              # Task D: Hardware clock-stretch timeout [FROZEN]
├── sim/
│   ├── filelist.f                                  # SystemVerilog simulation source manifest
│   ├── run_all_regressions.bat                     # Windows automated regression runner (293 checks)
│   ├── run_all_regressions.sh                      # Linux/macOS automated regression runner
│   ├── run_phase1.bat                              # Standalone Task A test runner
│   ├── run_phase1.sh                               # Standalone Task A shell script
│   ├── task_a_simulation.log                       # Golden simulation log (46 checks passed)
│   ├── task_b_simulation.log                       # Golden simulation log (49 checks passed)
│   ├── task_c_simulation.log                       # Supplementary baseline log (62 checks passed)
│   ├── task_d_simulation.log                       # Golden simulation log (93 checks passed)
│   ├── task_d_timeout_unit_simulation.log          # Golden simulation log (37 checks passed)
│   └── task_e_top_simulation.log                   # Golden simulation log (68 checks passed)
├── tb/
│   ├── ahb_tasks.svh                               # Reusable AHB-Lite bus driver BFM tasks
│   ├── i2c_slave_model.sv                          # External behavioral I2C slave model
│   ├── tb_ahb_registers.sv                         # Task A: AHB slave & register testbench
│   ├── tb_i2c_clock_gen.sv                         # Task B: Clock generator testbench
│   ├── tb_i2c_master.sv                            # Task C/D: Master core integration testbench
│   ├── tb_i2c_master_top.sv                        # Task E: Full-chip top-level testbench
│   └── tb_i2c_timeout.sv                           # Task D: Timeout unit testbench
└── tools/
    └── README.md                                   # Toolchain setup guide (Icarus Verilog & GTKWave)
```

---

## 4. Verification Regression Sign-Off

Prior to and immediately following the rebase, the complete system regression runner (`sim/run_all_regressions.bat`) was executed against the rebased codebase. The results confirmed **293 / 293 dynamic assertions passed with zero failures**:

| # | Regression Suite | Target Module | Scope & Focus Areas | Checks | Failures | Status |
|---|---|---|---|:---:|:---:|:---:|
| 1 | **Task A** | `ahb_lite_slave_if` + `i2c_registers` | AHB-Lite single-wait-state pipelining, 32-bit register reset values, R/W access, read-on-clear, W1C interrupt logic, invalid address OKAY response. | **46** | 0 | **PASSED** |
| 2 | **Task B** | `i2c_clock_gen` | Independent HIGH/LOW timing counters, zero-count hardware clamping (clamped to 1), clock stretching pause, synchronous abort recovery. | **49** | 0 | **PASSED** |
| 3 | **Task D Unit** | `i2c_timeout` | Hardware clock-stretching timeout detection, zero-timeout disabling, threshold saturation, synchronous abort recovery. | **37** | 0 | **PASSED** |
| 4 | **Tasks C & D Core** | `i2c_master` (integrated) | Standard (100 kHz) & Fast Mode (400 kHz) transactions, 7-bit addressing, repeated START, NACK handling, timeout abort, interrupt generation. | **93** | 0 | **PASSED** |
| 5 | **Task E Top** | `i2c_master_top` | Full-chip AHB-to-I2C loopback through external `i2c_slave_model`, open-drain tri-state bidirectional buffers, end-to-end interrupt assertion & clearing. | **68** | 0 | **PASSED** |
| **Total** | **Full System Regression** | **All Modules** | **Complete Design Verification Matrix** | **293** | **0** | **PASSED** |

*Note on Supplementary Evidence:* An additional Task C standalone baseline log (`sim/task_c_simulation.log`, 62 checks) is retained in the repository as supplementary design evidence, strictly segregated from the official 293-check regression total.

---

## 5. Architectural & Implementation Compliance

1. **RTL Freeze Status:** All six underlying modules developed during Tasks A through D (`rtl/i2c_pkg.sv`, `rtl/ahb_lite_slave_if.sv`, `rtl/i2c_registers.sv`, `rtl/i2c_clock_gen.sv`, `rtl/i2c_timeout.sv`, and `rtl/i2c_master.sv`) are officially frozen and untouched.
2. **Top-Level Integration:** `rtl/i2c_master_top.sv` strictly instantiates the three peer modules (`ahb_lite_slave_if`, `i2c_registers`, and `i2c_master`) without redundant clock generator or timeout instantiations.
3. **Target Platforms:** FPGA (Xilinx Artix-7 / Basys-3, Intel Cyclone IV) and ASIC (SkyWater 130nm) platforms are clearly identified in documentation as candidate evaluation targets, pending final physical design selection.
4. **Licensing:** Standard open-source licenses (MIT/Apache) have been intentionally omitted pending explicit institutional or project maintainer direction.

---

## 6. Conclusion

The GitHub repository `https://github.com/bhanderi-darshan/Capstone-Project-.git` has been professionally reconciled, rebased, validated, and published. The project structure is clean, modular, and fully aligned with professional ASIC/FPGA digital design standards.
