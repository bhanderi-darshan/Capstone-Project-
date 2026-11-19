@echo off
REM ============================================================================
REM Script:     run_phase1.bat
REM Project:    AHB-Lite to I2C Master Controller (Phase 1)
REM Description: Windows script to compile and run Phase 1 testbench
REM ============================================================================

set SCRIPT_DIR=%~dp0
set PRJ_DIR=%SCRIPT_DIR%..
cd "%PRJ_DIR%"

echo [INFO] Compiling Phase 1 RTL and Testbench using Icarus Verilog...
if exist tools\iverilog\bin\iverilog.exe (
    set IVERILOG_CMD=tools\iverilog\bin\iverilog.exe
    set VVP_CMD=tools\iverilog\bin\vvp.exe
) else (
    set IVERILOG_CMD=iverilog
    set VVP_CMD=vvp
)

%IVERILOG_CMD% -g2012 -o sim\tb_ahb_registers.vvp -f sim\filelist.f
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Compilation failed!
    exit /b %ERRORLEVEL%
)

echo [INFO] Running Phase 1 Simulation...
%VVP_CMD% sim\tb_ahb_registers.vvp
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Simulation encountered errors!
    exit /b %ERRORLEVEL%
)

echo [INFO] Simulation completed successfully!
pause
