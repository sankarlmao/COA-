#!/bin/bash
#==============================================================================
# RISC-V Load Store Unit - Quick Run Script
# Author: COA Project
# Date: March 2026
#==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║       RISC-V Load Store Unit - Quick Run                      ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

cd "$PROJECT_DIR"

# Check for Icarus Verilog
if ! command -v iverilog &> /dev/null; then
    echo "[ERROR] Icarus Verilog not found!"
    echo "Please install it with: sudo apt install iverilog"
    exit 1
fi

# Create sim directory
mkdir -p sim

# Compile
echo "[1/3] Compiling..."
iverilog -g2012 -Wall -Iinclude \
    include/lsu_pkg.sv \
    rtl/address_generation_unit.sv \
    rtl/load_buffer.sv \
    rtl/store_buffer.sv \
    rtl/memory_controller.sv \
    rtl/data_memory.sv \
    rtl/lsu_top.sv \
    tb/lsu_tb.sv \
    -o sim/lsu_sim

echo "[2/3] Running simulation..."
cd sim
vvp lsu_sim

echo ""
echo "[3/3] Simulation complete!"
echo "      VCD file: sim/lsu_tb.vcd"
echo "      View with: gtkwave sim/lsu_tb.vcd"
echo ""
