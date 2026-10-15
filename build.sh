#!/usr/bin/env bash
# Build and flash adc_fir_uart_top. Run from the repo root inside the OSS CAD Suite environment.
set -euo pipefail
TOP=adc_fir_uart_top
mkdir -p build
yosys -p "read_verilog rtl/adc_fir_uart_top.v rtl/mcp3008_spi_master.v rtl/sample_rate_timer.v rtl/fir_filter_31tap_tm_triggered.v rtl/sample_tx.v rtl/uart_tx.v; synth_gowin -top $TOP -json build/$TOP.json"
nextpnr-himbaechel --json build/$TOP.json --write build/${TOP}_routed.json \
  --device GW1NR-LV9QN88PC6/I5 --vopt family=GW1N-9C --vopt cst=constraints/$TOP.cst
gowin_pack -d GW1N-9C -o build/$TOP.fs build/${TOP}_routed.json
openFPGALoader -b tangnano9k build/$TOP.fs
