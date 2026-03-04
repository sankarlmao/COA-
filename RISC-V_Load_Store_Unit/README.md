# RISC-V Load Store Unit (LSU) Design Project

## Computer Organization and Architecture (COA) Project

### Author: COA Student Project
### Date: March 2026

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [RISC-V Load/Store Instructions](#2-risc-v-loadstore-instructions)
3. [Architecture Overview](#3-architecture-overview)
4. [Module Descriptions](#4-module-descriptions)
5. [Design Details](#5-design-details)
6. [Installation & Setup](#6-installation--setup)
7. [Running Simulations](#7-running-simulations)
8. [Verification Results](#8-verification-results)
9. [Block Diagrams](#9-block-diagrams)
10. [Future Enhancements](#10-future-enhancements)
11. [References](#11-references)

---

## 1. Introduction

### 1.1 Project Overview

This project implements a **Load Store Unit (LSU)** for a RISC-V processor. The LSU is a critical component in modern processors responsible for handling all memory access operations - both loads (reading data from memory) and stores (writing data to memory).

### 1.2 Objectives

- Design a functional LSU for RV32I base instruction set
- Implement all standard load instructions (LB, LH, LW, LBU, LHU)
- Implement all standard store instructions (SB, SH, SW)
- Support proper memory alignment checking
- Implement load and store buffers for out-of-order execution support
- Demonstrate store-to-load forwarding capability

### 1.3 Key Features

| Feature | Description |
|---------|-------------|
| **ISA Support** | RV32I Load/Store instructions |
| **Data Width** | 32-bit |
| **Address Width** | 32-bit (4GB address space) |
| **Load Buffer** | 4 entries, supports out-of-order completion |
| **Store Buffer** | 4 entries, in-order commit |
| **Forwarding** | Store-to-load forwarding supported |
| **Exceptions** | Misalignment detection |

---

## 2. RISC-V Load/Store Instructions

### 2.1 Load Instructions

| Instruction | funct3 | Description | Operation |
|------------|--------|-------------|-----------|
| **LB** | 000 | Load Byte (signed) | rd = SignExt(Mem[rs1+imm][7:0]) |
| **LH** | 001 | Load Halfword (signed) | rd = SignExt(Mem[rs1+imm][15:0]) |
| **LW** | 010 | Load Word | rd = Mem[rs1+imm][31:0] |
| **LBU** | 100 | Load Byte Unsigned | rd = ZeroExt(Mem[rs1+imm][7:0]) |
| **LHU** | 101 | Load Halfword Unsigned | rd = ZeroExt(Mem[rs1+imm][15:0]) |

### 2.2 Store Instructions

| Instruction | funct3 | Description | Operation |
|------------|--------|-------------|-----------|
| **SB** | 000 | Store Byte | Mem[rs1+imm][7:0] = rs2[7:0] |
| **SH** | 001 | Store Halfword | Mem[rs1+imm][15:0] = rs2[15:0] |
| **SW** | 010 | Store Word | Mem[rs1+imm][31:0] = rs2[31:0] |

### 2.3 Instruction Format

```
Load:   [imm[11:0]][rs1][funct3][rd][opcode=0000011]
Store:  [imm[11:5]][rs2][rs1][funct3][imm[4:0]][opcode=0100011]
```

### 2.4 Alignment Requirements

| Access Type | Address Requirement | Example Valid Addresses |
|-------------|---------------------|------------------------|
| Byte | Any | 0x0, 0x1, 0x2, 0x3 |
| Halfword | addr[0] = 0 | 0x0, 0x2, 0x4, 0x6 |
| Word | addr[1:0] = 00 | 0x0, 0x4, 0x8, 0xC |

---

## 3. Architecture Overview

### 3.1 System Block Diagram

```
                    ┌─────────────────────────────────────────┐
                    │              CPU PIPELINE               │
                    │    (Execution Unit / Memory Stage)      │
                    └──────────────────┬──────────────────────┘
                                       │
                    ┌──────────────────▼──────────────────────┐
                    │                                         │
                    │           LOAD STORE UNIT (LSU)         │
                    │                                         │
                    │  ┌─────────────────────────────────┐   │
                    │  │   Address Generation Unit (AGU)  │   │
                    │  │   - Effective Address Calc       │   │
                    │  │   - Alignment Checking           │   │
                    │  │   - Byte Enable Generation       │   │
                    │  └────────────────┬────────────────┘   │
                    │                   │                     │
                    │      ┌────────────┼────────────┐       │
                    │      │            │            │       │
                    │      ▼            │            ▼       │
                    │  ┌────────┐       │       ┌────────┐   │
                    │  │  LOAD  │       │       │ STORE  │   │
                    │  │ BUFFER │       │       │ BUFFER │   │
                    │  └───┬────┘       │       └───┬────┘   │
                    │      │            │            │       │
                    │      └────────────┼────────────┘       │
                    │                   │                     │
                    │      ┌────────────▼────────────┐       │
                    │      │   Memory Controller      │       │
                    │      │   - Request Arbitration  │       │
                    │      │   - Response Routing     │       │
                    │      └────────────┬────────────┘       │
                    │                   │                     │
                    └───────────────────┼─────────────────────┘
                                        │
                    ┌───────────────────▼─────────────────────┐
                    │            DATA MEMORY / CACHE          │
                    └─────────────────────────────────────────┘
```

### 3.2 Data Flow

1. **Request Reception**: LSU receives load/store requests from CPU execution unit
2. **Address Calculation**: AGU computes effective address (base + offset)
3. **Alignment Check**: Verify address alignment based on access size
4. **Buffer Allocation**: Load/Store request allocated to respective buffer
5. **Memory Access**: Memory controller arbitrates and issues memory requests
6. **Response Handling**: Data returned and processed (sign extension for loads)
7. **Writeback**: Result written back to CPU (register file for loads)

---

## 4. Module Descriptions

### 4.1 Top Module (`lsu_top.sv`)

The top-level module integrates all LSU components and manages the overall control flow.

**Ports:**

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | Input | 1 | System clock |
| `rst_n` | Input | 1 | Active-low reset |
| `cpu_req_valid_i` | Input | 1 | CPU request valid |
| `cpu_req_we_i` | Input | 1 | Write enable (1=Store) |
| `cpu_req_base_addr_i` | Input | 32 | Base address |
| `cpu_req_offset_i` | Input | 12 | Signed offset |
| `cpu_req_wdata_i` | Input | 32 | Store data |
| `cpu_req_funct3_i` | Input | 3 | Operation type |
| `cpu_req_rd_i` | Input | 5 | Destination register |
| `cpu_resp_valid_o` | Output | 1 | Response valid |
| `cpu_resp_rdata_o` | Output | 32 | Load data |
| `mem_req_*` | Output | - | Memory interface |
| `mem_resp_*` | Input | - | Memory response |

### 4.2 Address Generation Unit (`address_generation_unit.sv`)

Computes effective address and performs alignment checking.

**Functions:**
- Computes: `effective_address = base_address + sign_extend(offset)`
- Generates byte enable signals based on address LSBs and access size
- Detects misaligned accesses

### 4.3 Load Buffer (`load_buffer.sv`)

Manages pending load requests.

**Features:**
- FIFO-based storage with 4 entries
- Supports out-of-order completion
- In-order writeback to maintain program order
- Store-to-load hazard detection

### 4.4 Store Buffer (`store_buffer.sv`)

Manages pending store requests.

**Features:**
- FIFO-based storage with 4 entries
- Two-phase commit (allocate → commit → write)
- Store-to-load forwarding support
- Selective flush (only uncommitted stores)

### 4.5 Memory Controller (`memory_controller.sv`)

Arbitrates between load and store requests.

**Arbitration Policy:**
- Stores have priority (to maintain memory ordering)
- Round-robin when both have pending requests

### 4.6 Data Memory (`data_memory.sv`)

Simple memory model for simulation.

**Features:**
- Configurable depth and latency
- Byte-enable write support
- Optional memory initialization file

---

## 5. Design Details

### 5.1 FSM States

```
         ┌─────────┐
    ─────▶  IDLE   │◀─────────────────────────┐
         └────┬────┘                          │
              │ request valid                 │
              ▼                               │
         ┌─────────┐                          │
         │ADDR_CALC│                          │
         └────┬────┘                          │
              │                               │
         ┌────┴────┐                          │
         │         │                          │
    aligned    misaligned                     │
         │         │                          │
         ▼         ▼                          │
    ┌─────────┐  ┌─────────┐                  │
    │ MEM_REQ │  │  ERROR  │──────────────────┤
    └────┬────┘  └─────────┘                  │
         │                                    │
         │ buffer ready                       │
         └────────────────────────────────────┘
```

### 5.2 Store-to-Load Forwarding

When a load occurs, the store buffer is checked for matching addresses:

```
Load Address ──▶ Store Buffer Search (newest to oldest)
                        │
                   ┌────┴────┐
                   │  Match? │
                   └────┬────┘
                  No    │    Yes
                   │    │     │
                   ▼    │     ▼
              Memory    │  Forward
              Access    │  Data
                   │    │     │
                   └────┼─────┘
                        ▼
                   [Result]
```

### 5.3 Memory Alignment

Alignment checking logic:
```systemverilog
function check_alignment(addr, size);
    case (size)
        BYTE: return 1;                    // Always aligned
        HALF: return (addr[0] == 0);       // 2-byte aligned
        WORD: return (addr[1:0] == 0);     // 4-byte aligned
    endcase
endfunction
```

### 5.4 Sign Extension

Load data is sign/zero extended based on funct3:

```
LB:  data[31:0] = {{24{byte[7]}}, byte[7:0]}    // Sign extend byte
LH:  data[31:0] = {{16{half[15]}}, half[15:0]}  // Sign extend halfword
LW:  data[31:0] = word[31:0]                     // No extension needed
LBU: data[31:0] = {24'b0, byte[7:0]}            // Zero extend byte
LHU: data[31:0] = {16'b0, half[15:0]}           // Zero extend halfword
```

---

## 6. Installation & Setup

### 6.1 Prerequisites

**Required Tools:**
- **Icarus Verilog** (v11.0+) - Open-source Verilog simulator
- **GTKWave** (v3.3+) - Waveform viewer

**Optional Tools:**
- **Verilator** - For linting and faster simulation
- **ModelSim/QuestaSim** - Commercial simulator

### 6.2 Installing on Ubuntu/Debian

```bash
# Update package list
sudo apt update

# Install Icarus Verilog
sudo apt install iverilog

# Install GTKWave
sudo apt install gtkwave

# (Optional) Install Verilator
sudo apt install verilator
```

### 6.3 Installing on Fedora/RHEL

```bash
# Install Icarus Verilog
sudo dnf install iverilog

# Install GTKWave
sudo dnf install gtkwave

# (Optional) Install Verilator
sudo dnf install verilator
```

### 6.4 Installing on macOS

```bash
# Using Homebrew
brew install icarus-verilog
brew install gtkwave
brew install verilator
```

### 6.5 Verify Installation

```bash
# Check Icarus Verilog
iverilog -V

# Check VVP (Verilog runtime)
vvp -V

# Check GTKWave
gtkwave --version
```

---

## 7. Running Simulations

### 7.1 Using Make (Recommended)

```bash
# Navigate to project directory
cd RISC-V_Load_Store_Unit

# See available commands
make help

# Compile the design
make compile

# Run simulation
make sim

# Or compile and run in one command
make run

# View waveforms
make wave
```

### 7.2 Using Quick Run Script

```bash
# Make script executable
chmod +x scripts/run_sim.sh

# Run simulation
./scripts/run_sim.sh
```

### 7.3 Manual Commands

```bash
# Step 1: Create simulation directory
mkdir -p sim

# Step 2: Compile with Icarus Verilog
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

# Step 3: Run simulation
cd sim
vvp lsu_sim

# Step 4: View waveforms
gtkwave lsu_tb.vcd
```

### 7.4 Expected Output

```
╔═══════════════════════════════════════════════════════════╗
║       RISC-V Load Store Unit - Testbench                  ║
║                   COA Project                             ║
╚═══════════════════════════════════════════════════════════╝

[0] Applying reset...
[50] Reset complete

========== TEST 1: Basic Word Store/Load ==========
[60] STORE WORD: addr=0x00000100, data=0xDEADBEEF
[150] LOAD WORD: addr=0x00000100, rd=x1
[200] LOAD COMPLETE: data=0xDEADBEEF, rd=x1
[PASS] Word Store/Load: Expected=0xDEADBEEF, Got=0xDEADBEEF
...

╔═══════════════════════════════════════════════════════════╗
║                    TEST SUMMARY                           ║
╠═══════════════════════════════════════════════════════════╣
║  Total Tests:   10                                        ║
║  Passed:        10                                        ║
║  Failed:         0                                        ║
╚═══════════════════════════════════════════════════════════╝

*** ALL TESTS PASSED ***
```

### 7.5 Viewing Waveforms

After simulation, open GTKWave:

```bash
gtkwave sim/lsu_tb.vcd
```

**Recommended signals to observe:**
- `clk`, `rst_n` - Clock and reset
- `cpu_req_valid`, `cpu_req_ready` - Request handshake
- `cpu_resp_valid`, `cpu_resp_rdata` - Response
- `mem_req_*` - Memory interface signals
- `state` (in lsu_top) - FSM state

---

## 8. Verification Results

### 8.1 Test Cases

| Test | Description | Status |
|------|-------------|--------|
| Basic Word Access | SW/LW with aligned addresses | ✓ Pass |
| Byte Access | SB/LB with different byte positions | ✓ Pass |
| Halfword Access | SH/LH with alignment | ✓ Pass |
| Address Offset | Base + offset calculation | ✓ Pass |
| Multiple Operations | Sequence of stores and loads | ✓ Pass |
| Sign Extension | LB/LH with negative values | ✓ Pass |
| Zero Extension | LBU/LHU operations | ✓ Pass |

### 8.2 Coverage

- All RV32I load instructions tested
- All RV32I store instructions tested
- Different access sizes validated
- Address alignment verified
- Sign/zero extension confirmed

---

## 9. Block Diagrams

### 9.1 Detailed LSU Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                           LSU TOP MODULE                                  │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│    CPU REQUEST                                                           │
│    ─────────────                                                         │
│    ┌──────────────────────────────────────────────────────────────┐     │
│    │  valid | we | base_addr | offset | wdata | funct3 | rd       │     │
│    └────────────────────────────┬─────────────────────────────────┘     │
│                                 │                                        │
│                                 ▼                                        │
│    ┌──────────────────────────────────────────────────────────────┐     │
│    │              ADDRESS GENERATION UNIT (AGU)                    │     │
│    │  ┌─────────────────────────────────────────────────────────┐ │     │
│    │  │  eff_addr = base_addr + sign_extend(offset)             │ │     │
│    │  │  aligned  = check_alignment(eff_addr, size)             │ │     │
│    │  │  byte_en  = gen_byte_enable(eff_addr[1:0], size)        │ │     │
│    │  └─────────────────────────────────────────────────────────┘ │     │
│    └────────────────────────────┬─────────────────────────────────┘     │
│                                 │                                        │
│              ┌──────────────────┼──────────────────┐                     │
│              │                  │                  │                     │
│              ▼                  │                  ▼                     │
│    ┌─────────────────┐         │         ┌─────────────────┐            │
│    │   LOAD BUFFER   │         │         │  STORE BUFFER   │            │
│    │  ┌───────────┐  │         │         │  ┌───────────┐  │            │
│    │  │ Entry 0   │  │         │         │  │ Entry 0   │  │            │
│    │  │ Entry 1   │  │◀────────┼────────▶│  │ Entry 1   │  │            │
│    │  │ Entry 2   │  │  Forward│         │  │ Entry 2   │  │            │
│    │  │ Entry 3   │  │         │         │  │ Entry 3   │  │            │
│    │  └───────────┘  │         │         │  └───────────┘  │            │
│    └────────┬────────┘         │         └────────┬────────┘            │
│             │                  │                  │                     │
│             └──────────────────┼──────────────────┘                     │
│                                │                                        │
│                                ▼                                        │
│    ┌──────────────────────────────────────────────────────────────┐     │
│    │                   MEMORY CONTROLLER                           │     │
│    │  ┌─────────────────────────────────────────────────────────┐ │     │
│    │  │  Arbitration: Store Priority > Load                     │ │     │
│    │  │  Request Mux  → Memory Interface                        │ │     │
│    │  │  Response Demux ← Memory Response                       │ │     │
│    │  └─────────────────────────────────────────────────────────┘ │     │
│    └────────────────────────────┬─────────────────────────────────┘     │
│                                 │                                        │
└─────────────────────────────────┼────────────────────────────────────────┘
                                  │
                                  ▼
                        ┌─────────────────┐
                        │   DATA MEMORY   │
                        │    / CACHE      │
                        └─────────────────┘
```

### 9.2 Load Buffer Entry Format

```
┌─────────────────────────────────────────────────────────────┐
│                    LOAD BUFFER ENTRY (48 bits)              │
├──────┬─────────┬────────────────────┬────────┬──────────────┤
│valid │ pending │     address        │ funct3 │     rd       │
│ (1)  │   (1)   │      (32)          │  (3)   │    (5)       │
├──────┼─────────┼────────────────────┼────────┼──────────────┤
│  1   │    1    │  0x0000_0100       │  010   │   00001      │
└──────┴─────────┴────────────────────┴────────┴──────────────┘

valid:   Entry contains valid request
pending: Waiting for memory response
address: Effective memory address
funct3:  Load type (LB/LH/LW/LBU/LHU)
rd:      Destination register number
```

### 9.3 Store Buffer Entry Format

```
┌─────────────────────────────────────────────────────────────────────┐
│                    STORE BUFFER ENTRY (73 bits)                     │
├──────┬───────────┬────────────────────┬──────────────────────┬──────┤
│valid │ committed │     address        │        data          │  be  │
│ (1)  │    (1)    │      (32)          │        (32)          │ (4)  │
├──────┼───────────┼────────────────────┼──────────────────────┼──────┤
│  1   │     1     │  0x0000_0200       │   0xDEAD_BEEF        │ 1111 │
└──────┴───────────┴────────────────────┴──────────────────────┴──────┘

valid:     Entry contains valid request
committed: Instruction has been committed (can be written to memory)
address:   Effective memory address
data:      Data to be stored
be:        Byte enable (which bytes to write)
```

---

## 10. Future Enhancements

### 10.1 Potential Improvements

1. **Cache Integration**
   - Add L1 data cache interface
   - Support cache hit/miss handling
   - Implement write-back/write-through policies

2. **RV64 Support**
   - Extend to 64-bit data width
   - Add LD/SD instructions

3. **Memory Protection**
   - Add PMP (Physical Memory Protection) checks
   - Implement access permission verification

4. **Performance Optimizations**
   - Increase buffer depths
   - Add multiple memory ports
   - Implement non-blocking loads

5. **Exception Handling**
   - Add page fault support
   - Implement precise exceptions

### 10.2 Extension to Full Processor

This LSU can be integrated into a complete RV32I processor with:
- Instruction Fetch Unit
- Decode Stage
- Execution Units (ALU, Branch, etc.)
- Register File
- Control and Hazard Detection

---

## 11. References

### 11.1 RISC-V Specifications

1. **RISC-V User-Level ISA Specification** (v2.2)
   - Chapter 2: RV32I Base Integer Instruction Set
   - Section 2.6: Load and Store Instructions

2. **RISC-V Privileged Architecture** (v1.10)
   - Exception handling for load/store

### 11.2 Recommended Reading

- "Computer Organization and Design: RISC-V Edition" - Patterson & Hennessy
- "Digital Design and Computer Architecture: RISC-V Edition" - Harris & Harris
- RISC-V International: https://riscv.org/

### 11.3 Online Resources

- RISC-V ISA Manual: https://riscv.org/technical/specifications/
- Icarus Verilog: http://iverilog.icarus.com/
- GTKWave: http://gtkwave.sourceforge.net/

---

## Project Structure

```
RISC-V_Load_Store_Unit/
├── Makefile                    # Build automation
├── README.md                   # This documentation
├── include/
│   └── lsu_pkg.sv             # Package with types and constants
├── rtl/
│   ├── address_generation_unit.sv
│   ├── load_buffer.sv
│   ├── store_buffer.sv
│   ├── memory_controller.sv
│   ├── data_memory.sv
│   └── lsu_top.sv
├── tb/
│   └── lsu_tb.sv              # Testbench
├── sim/                        # Simulation outputs
├── scripts/
│   └── run_sim.sh             # Quick run script
└── docs/
    └── (additional documentation)
```

---

## Quick Start Commands

```bash
# Clone/Navigate to project
cd RISC-V_Load_Store_Unit

# Run everything
make run

# View waveforms
make wave
```

---

**© 2026 COA Project - RISC-V Load Store Unit Design**
