#!/usr/bin/env bash
# ============================================================================
# Script:     run_phase1.sh
# Project:    AHB-Lite to I2C Master Controller (Phase 1)
# Description: Linux/Ubuntu script to compile and run Phase 1 testbench
# ============================================================================

set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PRJ_DIR="${SCRIPT_DIR}/.."
cd "${PRJ_DIR}"

echo "[INFO] Compiling Phase 1 RTL and Testbench using Icarus Verilog..."
iverilog -g2012 -o sim/tb_ahb_registers.vvp -f sim/filelist.f

echo "[INFO] Running Phase 1 Simulation with vvp..."
vvp sim/tb_ahb_registers.vvp

echo "[INFO] Simulation completed successfully! Waveform written to sim/tb_ahb_registers.vcd"
