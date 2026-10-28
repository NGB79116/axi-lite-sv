@echo off
rem Compile and run the AXI4-Lite slave testbench (Icarus Verilog 12).
rem The old binary is deleted first so a failed compile can't run a stale one.
cd /d "%~dp0"
if exist axi_sim del axi_sim
iverilog -g2012 -o axi_sim rtl\axi_lite_slave.sv tb\axi_lite_sva.sv tb\axi_lite_coverage.sv tb\axi_lite_tb.sv
if errorlevel 1 (
  echo *** Compile failed ***
  exit /b 1
)
vvp axi_sim
