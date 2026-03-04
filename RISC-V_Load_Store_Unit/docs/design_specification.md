# RISC-V Load Store Unit - Design Specification

## Document Information
- **Project:** RISC-V Load Store Unit
- **Version:** 1.0
- **Date:** March 2026
- **Course:** Computer Organization and Architecture (COA)

---

## 1. Design Requirements

### 1.1 Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-001 | Support all RV32I load instructions (LB, LH, LW, LBU, LHU) | Must |
| FR-002 | Support all RV32I store instructions (SB, SH, SW) | Must |
| FR-003 | Compute effective address from base + 12-bit signed offset | Must |
| FR-004 | Detect misaligned memory accesses | Must |
| FR-005 | Generate appropriate exceptions for misalignment | Must |
| FR-006 | Support store-to-load forwarding | Should |
| FR-007 | Buffer multiple outstanding memory requests | Should |
| FR-008 | Maintain memory ordering (stores commit in order) | Must |

### 1.2 Interface Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| IR-001 | Synchronous design with single clock domain | Must |
| IR-002 | Active-low asynchronous reset | Must |
| IR-003 | Ready/valid handshaking on CPU interface | Must |
| IR-004 | Ready/valid handshaking on memory interface | Must |
| IR-005 | Configurable memory latency support | Should |

### 1.3 Performance Requirements

| ID | Requirement | Target |
|----|-------------|--------|
| PR-001 | Load latency (no forwarding) | 2-3 cycles + memory |
| PR-002 | Store latency | 1 cycle (to buffer) |
| PR-003 | Buffer depth | 4 entries minimum |
| PR-004 | Clock frequency target | 100 MHz |

---

## 2. Interface Specification

### 2.1 CPU Request Interface

```systemverilog
// Request signals (CPU → LSU)
input  logic                    cpu_req_valid_i,    // Request valid
input  logic                    cpu_req_we_i,       // 1=Store, 0=Load
input  logic [31:0]             cpu_req_base_addr_i,// Base address (rs1)
input  logic [11:0]             cpu_req_offset_i,   // Signed offset (imm)
input  logic [31:0]             cpu_req_wdata_i,    // Store data (rs2)
input  logic [2:0]              cpu_req_funct3_i,   // Operation type
input  logic [4:0]              cpu_req_rd_i,       // Destination reg (loads)
output logic                    cpu_req_ready_o,    // LSU ready to accept
```

### 2.2 CPU Response Interface

```systemverilog
// Response signals (LSU → CPU)
output logic                    cpu_resp_valid_o,   // Response valid
output logic [31:0]             cpu_resp_rdata_o,   // Load data
output logic [4:0]              cpu_resp_rd_o,      // Destination register
output logic                    cpu_resp_error_o,   // Exception occurred
output logic [3:0]              cpu_resp_exc_code_o,// Exception code
input  logic                    cpu_resp_ready_i,   // CPU ready to accept
```

### 2.3 Memory Interface

```systemverilog
// Memory request (LSU → Memory)
output logic                    mem_req_valid_o,
output logic                    mem_req_we_o,       // Write enable
output logic [31:0]             mem_req_addr_o,     // Address
output logic [31:0]             mem_req_wdata_o,    // Write data
output logic [3:0]              mem_req_be_o,       // Byte enable

// Memory response (Memory → LSU)
input  logic                    mem_req_ready_i,
input  logic                    mem_resp_valid_i,
input  logic [31:0]             mem_resp_rdata_i,
input  logic                    mem_resp_error_i,
```

### 2.4 Control Interface

```systemverilog
input  logic                    commit_i,           // Commit oldest store
input  logic                    flush_i,            // Flush on misprediction
output logic                    lsu_busy_o,         // LSU has pending ops
output logic                    load_buffer_full_o, // Load buffer full
output logic                    store_buffer_full_o,// Store buffer full
```

---

## 3. Timing Diagrams

### 3.1 Basic Store Operation

```
        ┌───┐   ┌───┐   ┌───┐   ┌───┐   ┌───┐   ┌───┐   ┌───┐
clk     │   │   │   │   │   │   │   │   │   │   │   │   │   │
        ┘   └───┘   └───┘   └───┘   └───┘   └───┘   └───┘   └───

        ────────┐                                           
req_valid       │               
        ────────┘───────────────────────────────────────────

        ────────┐
req_we          │               
        ────────┘───────────────────────────────────────────

        ────────────────┐
req_ready               │       
        ────────────────┘───────────────────────────────────

                        ────────┐
commit                          │
                        ────────┘───────────────────────────

                                ────────┐
mem_req_valid                           │
                                ────────┘───────────────────

        │ Req  │ Addr │Buffer │Commit │ Mem  │ Done │
        │Accept│ Calc │Alloc  │       │Write │      │
```

### 3.2 Basic Load Operation

```
        ┌───┐   ┌───┐   ┌───┐   ┌───┐   ┌───┐   ┌───┐   ┌───┐
clk     │   │   │   │   │   │   │   │   │   │   │   │   │   │
        ┘   └───┘   └───┘   └───┘   └───┘   └───┘   └───┘   └───

        ────────┐                                           
req_valid       │               
        ────────┘───────────────────────────────────────────

                                ────────┐
mem_req_valid                           │
                                ────────┘───────────────────

                                        ────────┐
mem_resp_valid                                  │
                                        ────────┘───────────

                                                ────────┐
cpu_resp_valid                                          │
                                                ────────┘───

        │ Req  │ Addr │Buffer │ Mem  │ Mem  │Wrback│
        │Accept│ Calc │Alloc  │ Req  │ Resp │      │
```

---

## 4. Exception Handling

### 4.1 Exception Codes

| Code | Name | Cause |
|------|------|-------|
| 4 | Load Address Misaligned | LH/LW with unaligned address |
| 5 | Load Access Fault | Invalid memory access (load) |
| 6 | Store Address Misaligned | SH/SW with unaligned address |
| 7 | Store Access Fault | Invalid memory access (store) |

### 4.2 Exception Detection

```
Address Alignment Check:
- LB/SB: Always aligned (any address OK)
- LH/SH: addr[0] must be 0
- LW/SW: addr[1:0] must be 00

Exception raised when:
- Halfword access: addr[0] != 0
- Word access: addr[1:0] != 00
```

---

## 5. Register Definitions

### 5.1 Internal Registers

| Register | Width | Description |
|----------|-------|-------------|
| `state` | 3 | FSM state |
| `req_is_store_r` | 1 | Latched operation type |
| `req_addr_r` | 32 | Computed effective address |
| `req_wdata_r` | 32 | Latched store data |
| `req_funct3_r` | 3 | Latched funct3 |
| `req_rd_r` | 5 | Latched destination register |
| `req_be_r` | 4 | Computed byte enable |

### 5.2 Buffer Entry Fields

**Load Buffer Entry (42 bits):**
- `valid` [1]: Entry valid
- `pending` [1]: Waiting for memory
- `addr` [32]: Memory address
- `funct3` [3]: Load type
- `rd` [5]: Destination register

**Store Buffer Entry (70 bits):**
- `valid` [1]: Entry valid
- `committed` [1]: Ready for memory write
- `addr` [32]: Memory address
- `data` [32]: Store data
- `be` [4]: Byte enable

---

## 6. Synthesis Estimates

### 6.1 Resource Utilization (Estimated)

| Resource | Count | Notes |
|----------|-------|-------|
| Flip-Flops | ~800 | Registers and buffers |
| LUTs | ~600 | Combinational logic |
| BRAM | 0 | No block RAM needed |

### 6.2 Timing

| Metric | Target | Notes |
|--------|--------|-------|
| Clock Period | 10ns | 100 MHz |
| Setup Slack | > 1ns | Target |
| Hold Slack | > 0ns | Target |

---

## 7. Verification Strategy

### 7.1 Test Categories

1. **Basic Functionality**
   - Word/Halfword/Byte operations
   - All funct3 variants

2. **Address Calculation**
   - Positive and negative offsets
   - Boundary conditions

3. **Alignment**
   - Aligned accesses (pass)
   - Misaligned accesses (exception)

4. **Buffering**
   - Buffer fill conditions
   - Back-pressure handling

5. **Forwarding**
   - Store followed by load to same address
   - Partial forwarding scenarios

### 7.2 Coverage Goals

| Coverage Type | Target |
|---------------|--------|
| Code Coverage | > 95% |
| FSM Coverage | 100% |
| Toggle Coverage | > 90% |

---

## 8. Design Constraints

### 8.1 Design Rules

1. All registers reset to known values
2. No combinational loops
3. All outputs registered
4. Single clock domain
5. Synchronous reset for datapath
6. Asynchronous reset for control

### 8.2 Coding Standards

- SystemVerilog 2012 standard
- Explicit port declarations
- Named port connections
- Consistent naming convention:
  - `_i` suffix for inputs
  - `_o` suffix for outputs
  - `_r` suffix for registers
  - `_n` suffix for active-low signals

---

**End of Design Specification**
