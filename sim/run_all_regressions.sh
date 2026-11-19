#!/usr/bin/env bash
# ============================================================================
# Script:     run_all_regressions.sh
# Project:    AHB-Lite to I2C Master Controller
# Description: Comprehensive Linux/Ubuntu regression script executing all 5
#              verification suites (293 total dynamic checks).
# ============================================================================

set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PRJ_DIR="${SCRIPT_DIR}/.."
cd "${PRJ_DIR}"

echo "============================================================================"
echo "  STARTING FULL SYSTEM REGRESSION SUITE (293 CHECKS)"
echo "============================================================================"

# Check iverilog availability
if ! command -v iverilog &> /dev/null; then
    echo "[ERROR] iverilog compiler could not be found. Please install Icarus Verilog."
    exit 1
fi

# ----------------------------------------------------------------------------
# 1. Task A: AHB-Lite Slave Protocol & Register Bank (46 Checks)
# ----------------------------------------------------------------------------
echo ""
echo "[1/5] Compiling and Running Task A (AHB Slave & Registers - 46 Checks)..."
iverilog -g2012 -Wall -o sim/tb_ahb_registers.vvp \
    rtl/i2c_pkg.sv rtl/ahb_lite_slave_if.sv rtl/i2c_registers.sv tb/tb_ahb_registers.sv
vvp sim/tb_ahb_registers.vvp

# ----------------------------------------------------------------------------
# 2. Task B: Programmable I2C Clock Generator (49 Checks)
# ----------------------------------------------------------------------------
echo ""
echo "[2/5] Compiling and Running Task B (Clock Generator - 49 Checks)..."
iverilog -g2012 -Wall -o sim/tb_i2c_clock_gen.vvp \
    rtl/i2c_clock_gen.sv tb/tb_i2c_clock_gen.sv
vvp sim/tb_i2c_clock_gen.vvp

# ----------------------------------------------------------------------------
# 3. Task D Unit: Hardware Clock-Stretching Timeout (37 Checks)
# ----------------------------------------------------------------------------
echo ""
echo "[3/5] Compiling and Running Task D Unit (Timeout Engine - 37 Checks)..."
iverilog -g2012 -Wall -o sim/tb_i2c_timeout.vvp \
    rtl/i2c_timeout.sv tb/tb_i2c_timeout.sv
vvp sim/tb_i2c_timeout.vvp

# ----------------------------------------------------------------------------
# 4. Tasks C & D Integration: Master Controller Core (93 Checks)
# ----------------------------------------------------------------------------
echo ""
echo "[4/5] Compiling and Running Tasks C & D Integration (Master Core - 93 Checks)..."
iverilog -g2012 -Wall -o sim/tb_i2c_master.vvp \
    rtl/i2c_pkg.sv rtl/i2c_clock_gen.sv rtl/i2c_timeout.sv rtl/i2c_master.sv \
    rtl/i2c_registers.sv tb/i2c_slave_model.sv tb/tb_i2c_master.sv
vvp sim/tb_i2c_master.vvp

# ----------------------------------------------------------------------------
# 5. Task E: Full-Chip Top-Level Integration (68 Checks)
# ----------------------------------------------------------------------------
echo ""
echo "[5/5] Compiling and Running Task E (Full-Chip Top-Level - 68 Checks)..."
iverilog -g2012 -Wall -o sim/tb_i2c_master_top.vvp \
    rtl/i2c_pkg.sv rtl/ahb_lite_slave_if.sv rtl/i2c_registers.sv rtl/i2c_clock_gen.sv \
    rtl/i2c_timeout.sv rtl/i2c_master.sv rtl/i2c_master_top.sv tb/i2c_slave_model.sv tb/tb_i2c_master_top.sv
vvp sim/tb_i2c_master_top.vvp

echo ""
echo "============================================================================"
echo "  ALL 5 REGRESSION SUITES PASSED! (293 / 293 CHECKS VERIFIED)"
echo "============================================================================"
