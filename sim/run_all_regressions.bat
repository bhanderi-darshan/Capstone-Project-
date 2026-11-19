@echo off
REM ============================================================================
REM Script:     run_all_regressions.bat
REM Project:    AHB-Lite to I2C Master Controller
REM Description: Comprehensive Windows regression script executing all 5 suites
REM              (293 total dynamic checks).
REM ============================================================================

set SCRIPT_DIR=%~dp0
set PRJ_DIR=%SCRIPT_DIR%..
cd "%PRJ_DIR%"

echo ============================================================================
echo   STARTING FULL SYSTEM REGRESSION SUITE (293 CHECKS)
echo ============================================================================

if exist tools\iverilog\bin\iverilog.exe (
    set IVERILOG_CMD=tools\iverilog\bin\iverilog.exe
    set VVP_CMD=tools\iverilog\bin\vvp.exe
) else (
    set IVERILOG_CMD=iverilog
    set VVP_CMD=vvp
)

REM ----------------------------------------------------------------------------
REM 1. Task A: AHB-Lite Slave Protocol & Register Bank (46 Checks)
REM ----------------------------------------------------------------------------
echo.
echo [1/5] Compiling and Running Task A (AHB Slave and Registers - 46 Checks)...
%IVERILOG_CMD% -g2012 -Wall -o sim\tb_ahb_registers.vvp rtl\i2c_pkg.sv rtl\ahb_lite_slave_if.sv rtl\i2c_registers.sv tb\tb_ahb_registers.sv
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Task A compilation failed!
    exit /b %ERRORLEVEL%
)
%VVP_CMD% sim\tb_ahb_registers.vvp
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Task A simulation failed!
    exit /b %ERRORLEVEL%
)

REM ----------------------------------------------------------------------------
REM 2. Task B: Programmable I2C Clock Generator (49 Checks)
REM ----------------------------------------------------------------------------
echo.
echo [2/5] Compiling and Running Task B (Clock Generator - 49 Checks)...
%IVERILOG_CMD% -g2012 -Wall -o sim\tb_i2c_clock_gen.vvp rtl\i2c_clock_gen.sv tb\tb_i2c_clock_gen.sv
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Task B compilation failed!
    exit /b %ERRORLEVEL%
)
%VVP_CMD% sim\tb_i2c_clock_gen.vvp
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Task B simulation failed!
    exit /b %ERRORLEVEL%
)

REM ----------------------------------------------------------------------------
REM 3. Task D Unit: Hardware Clock-Stretching Timeout (37 Checks)
REM ----------------------------------------------------------------------------
echo.
echo [3/5] Compiling and Running Task D Unit (Timeout Engine - 37 Checks)...
%IVERILOG_CMD% -g2012 -Wall -o sim\tb_i2c_timeout.vvp rtl\i2c_timeout.sv tb\tb_i2c_timeout.sv
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Task D Unit compilation failed!
    exit /b %ERRORLEVEL%
)
%VVP_CMD% sim\tb_i2c_timeout.vvp
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Task D Unit simulation failed!
    exit /b %ERRORLEVEL%
)

REM ----------------------------------------------------------------------------
REM 4. Tasks C & D Integration: Master Controller Core (93 Checks)
REM ----------------------------------------------------------------------------
echo.
echo [4/5] Compiling and Running Tasks C and D Integration (Master Core - 93 Checks)...
%IVERILOG_CMD% -g2012 -Wall -o sim\tb_i2c_master.vvp rtl\i2c_pkg.sv rtl\i2c_clock_gen.sv rtl\i2c_timeout.sv rtl\i2c_master.sv rtl\i2c_registers.sv tb\i2c_slave_model.sv tb\tb_i2c_master.sv
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Tasks C & D compilation failed!
    exit /b %ERRORLEVEL%
)
%VVP_CMD% sim\tb_i2c_master.vvp
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Tasks C & D simulation failed!
    exit /b %ERRORLEVEL%
)

REM ----------------------------------------------------------------------------
REM 5. Task E: Full-Chip Top-Level Integration (68 Checks)
REM ----------------------------------------------------------------------------
echo.
echo [5/5] Compiling and Running Task E (Full-Chip Top-Level - 68 Checks)...
%IVERILOG_CMD% -g2012 -Wall -o sim\tb_i2c_master_top.vvp rtl\i2c_pkg.sv rtl\ahb_lite_slave_if.sv rtl\i2c_registers.sv rtl\i2c_clock_gen.sv rtl\i2c_timeout.sv rtl\i2c_master.sv rtl\i2c_master_top.sv tb\i2c_slave_model.sv tb\tb_i2c_master_top.sv
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Task E Top compilation failed!
    exit /b %ERRORLEVEL%
)
%VVP_CMD% sim\tb_i2c_master_top.vvp
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Task E Top simulation failed!
    exit /b %ERRORLEVEL%
)

echo.
echo ============================================================================
echo   ALL 5 REGRESSION SUITES PASSED! (293 / 293 CHECKS VERIFIED)
echo ============================================================================
