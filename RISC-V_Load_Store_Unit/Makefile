#==============================================================================
# Makefile for RISC-V Load Store Unit Project
# Supports: Icarus Verilog, Verilator, and ModelSim/QuestaSim
# Author: COA Project
# Date: March 2026
#==============================================================================

#------------------------------------------------------------------------------
# Project Configuration
#------------------------------------------------------------------------------
PROJECT_NAME := riscv_lsu
TOP_MODULE   := lsu_top
TB_MODULE    := lsu_tb

#------------------------------------------------------------------------------
# Directory Structure
#------------------------------------------------------------------------------
RTL_DIR      := rtl
TB_DIR       := tb
SIM_DIR      := sim
INCLUDE_DIR  := include
SCRIPTS_DIR  := scripts
DOCS_DIR     := docs

#------------------------------------------------------------------------------
# Source Files
#------------------------------------------------------------------------------
RTL_SOURCES := \
	$(INCLUDE_DIR)/lsu_pkg.sv \
	$(RTL_DIR)/address_generation_unit.sv \
	$(RTL_DIR)/load_buffer.sv \
	$(RTL_DIR)/store_buffer.sv \
	$(RTL_DIR)/memory_controller.sv \
	$(RTL_DIR)/data_memory.sv \
	$(RTL_DIR)/lsu_top.sv

TB_SOURCES := \
	$(TB_DIR)/lsu_tb.sv

ALL_SOURCES := $(RTL_SOURCES) $(TB_SOURCES)

#------------------------------------------------------------------------------
# Tool Configuration
#------------------------------------------------------------------------------
# Icarus Verilog
IVERILOG     := iverilog
VVP          := vvp
IVERILOG_FLAGS := -g2012 -Wall -I$(INCLUDE_DIR)

# Verilator
VERILATOR    := verilator
VERILATOR_FLAGS := --sv --timing -Wall -I$(INCLUDE_DIR)

# ModelSim/QuestaSim
VLOG         := vlog
VSIM         := vsim
VLIB         := vlib
VLOG_FLAGS   := -sv +incdir+$(INCLUDE_DIR)

# GTKWave (Waveform Viewer)
GTKWAVE      := gtkwave

#------------------------------------------------------------------------------
# Output Files
#------------------------------------------------------------------------------
SIM_EXEC     := $(SIM_DIR)/$(PROJECT_NAME)_sim
VCD_FILE     := $(SIM_DIR)/lsu_tb.vcd
LOG_FILE     := $(SIM_DIR)/simulation.log

#------------------------------------------------------------------------------
# Default Target
#------------------------------------------------------------------------------
.PHONY: all
all: help

#------------------------------------------------------------------------------
# Help
#------------------------------------------------------------------------------
.PHONY: help
help:
	@echo ""
	@echo "╔═══════════════════════════════════════════════════════════════╗"
	@echo "║     RISC-V Load Store Unit - Build System                     ║"
	@echo "╚═══════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "Available targets:"
	@echo ""
	@echo "  Simulation (Icarus Verilog):"
	@echo "    make compile      - Compile design with Icarus Verilog"
	@echo "    make sim          - Run simulation"
	@echo "    make wave         - Open waveform in GTKWave"
	@echo "    make run          - Compile and run simulation"
	@echo ""
	@echo "  Simulation (Verilator):"
	@echo "    make verilate     - Lint with Verilator"
	@echo ""
	@echo "  Simulation (ModelSim/QuestaSim):"
	@echo "    make msim_compile - Compile for ModelSim"
	@echo "    make msim_run     - Run ModelSim simulation"
	@echo ""
	@echo "  Utilities:"
	@echo "    make lint         - Run linting checks"
	@echo "    make clean        - Clean generated files"
	@echo "    make cleanall     - Clean all generated files and logs"
	@echo ""
	@echo "  Project Info:"
	@echo "    make sources      - List all source files"
	@echo "    make check_tools  - Check installed tools"
	@echo ""

#------------------------------------------------------------------------------
# Icarus Verilog Targets
#------------------------------------------------------------------------------
.PHONY: compile
compile: $(SIM_DIR)
	@echo "Compiling with Icarus Verilog..."
	$(IVERILOG) $(IVERILOG_FLAGS) -o $(SIM_EXEC) $(ALL_SOURCES)
	@echo "Compilation successful: $(SIM_EXEC)"

.PHONY: sim
sim: $(SIM_EXEC)
	@echo "Running simulation..."
	cd $(SIM_DIR) && $(VVP) ../$(SIM_EXEC) | tee simulation.log
	@echo "Simulation complete. Log: $(SIM_DIR)/simulation.log"

.PHONY: run
run: compile sim

.PHONY: wave
wave: $(SIM_DIR)/lsu_tb.vcd
	@echo "Opening waveform viewer..."
	$(GTKWAVE) $(SIM_DIR)/lsu_tb.vcd &

$(SIM_EXEC): $(ALL_SOURCES)
	@make compile

$(SIM_DIR)/lsu_tb.vcd: $(SIM_EXEC)
	@make sim

#------------------------------------------------------------------------------
# Verilator Targets
#------------------------------------------------------------------------------
.PHONY: verilate
verilate:
	@echo "Running Verilator lint..."
	$(VERILATOR) $(VERILATOR_FLAGS) --lint-only $(RTL_SOURCES)
	@echo "Verilator lint passed!"

#------------------------------------------------------------------------------
# ModelSim Targets
#------------------------------------------------------------------------------
MSIM_WORK := $(SIM_DIR)/work

.PHONY: msim_compile
msim_compile: $(MSIM_WORK)
	@echo "Compiling with ModelSim..."
	$(VLOG) $(VLOG_FLAGS) -work $(MSIM_WORK) $(ALL_SOURCES)

.PHONY: msim_run
msim_run: msim_compile
	@echo "Running ModelSim simulation..."
	$(VSIM) -c -do "run -all; quit" -work $(MSIM_WORK) $(TB_MODULE)

$(MSIM_WORK):
	$(VLIB) $(MSIM_WORK)

#------------------------------------------------------------------------------
# Lint Target
#------------------------------------------------------------------------------
.PHONY: lint
lint: verilate
	@echo "All lint checks passed!"

#------------------------------------------------------------------------------
# Directory Creation
#------------------------------------------------------------------------------
$(SIM_DIR):
	@mkdir -p $(SIM_DIR)

#------------------------------------------------------------------------------
# Utility Targets
#------------------------------------------------------------------------------
.PHONY: sources
sources:
	@echo "RTL Sources:"
	@for f in $(RTL_SOURCES); do echo "  $$f"; done
	@echo ""
	@echo "Testbench Sources:"
	@for f in $(TB_SOURCES); do echo "  $$f"; done

.PHONY: check_tools
check_tools:
	@echo "Checking installed tools..."
	@echo ""
	@which $(IVERILOG) > /dev/null 2>&1 && echo "[✓] Icarus Verilog: $$($(IVERILOG) -V 2>&1 | head -1)" || echo "[✗] Icarus Verilog: Not found"
	@which $(VERILATOR) > /dev/null 2>&1 && echo "[✓] Verilator: $$($(VERILATOR) --version)" || echo "[✗] Verilator: Not found"
	@which $(GTKWAVE) > /dev/null 2>&1 && echo "[✓] GTKWave: Found" || echo "[✗] GTKWave: Not found"
	@which $(VLOG) > /dev/null 2>&1 && echo "[✓] ModelSim: Found" || echo "[✗] ModelSim: Not found"
	@echo ""

#------------------------------------------------------------------------------
# Clean Targets
#------------------------------------------------------------------------------
.PHONY: clean
clean:
	@echo "Cleaning generated files..."
	rm -f $(SIM_DIR)/$(PROJECT_NAME)_sim
	rm -f $(SIM_DIR)/*.vcd
	rm -f $(SIM_DIR)/*.log
	rm -rf $(MSIM_WORK)
	@echo "Clean complete."

.PHONY: cleanall
cleanall: clean
	@echo "Cleaning all generated files..."
	rm -rf $(SIM_DIR)/*
	@echo "Clean all complete."

#------------------------------------------------------------------------------
# Quick Test
#------------------------------------------------------------------------------
.PHONY: test
test: run
	@echo ""
	@echo "Quick test complete!"
