//==============================================================================
// File: lsu_pkg.sv
// Description: Package containing type definitions, parameters, and constants
//              for the RISC-V Load Store Unit
// Author: COA Project
// Date: March 2026
//==============================================================================

`ifndef LSU_PKG_SV
`define LSU_PKG_SV

package lsu_pkg;

    //==========================================================================
    // Global Parameters
    //==========================================================================
    parameter XLEN         = 32;           // Data width (32 for RV32, 64 for RV64)
    parameter ADDR_WIDTH   = 32;           // Address width
    parameter DATA_WIDTH   = 32;           // Data bus width
    parameter MEM_DEPTH    = 4096;         // Memory depth (16KB)
    parameter BUFFER_DEPTH = 4;            // Load/Store buffer depth
    
    //==========================================================================
    // RISC-V Load/Store Instruction Opcodes
    //==========================================================================
    // Load instructions (opcode = 7'b0000011)
    parameter [2:0] FUNCT3_LB  = 3'b000;   // Load Byte (signed)
    parameter [2:0] FUNCT3_LH  = 3'b001;   // Load Halfword (signed)
    parameter [2:0] FUNCT3_LW  = 3'b010;   // Load Word
    parameter [2:0] FUNCT3_LBU = 3'b100;   // Load Byte Unsigned
    parameter [2:0] FUNCT3_LHU = 3'b101;   // Load Halfword Unsigned
    
    // Store instructions (opcode = 7'b0100011)
    parameter [2:0] FUNCT3_SB  = 3'b000;   // Store Byte
    parameter [2:0] FUNCT3_SH  = 3'b001;   // Store Halfword
    parameter [2:0] FUNCT3_SW  = 3'b010;   // Store Word

    //==========================================================================
    // Enumerated Types
    //==========================================================================
    
    // Memory operation type
    typedef enum logic [1:0] {
        MEM_OP_NONE  = 2'b00,
        MEM_OP_LOAD  = 2'b01,
        MEM_OP_STORE = 2'b10
    } mem_op_t;

    // Memory access size
    typedef enum logic [1:0] {
        MEM_SIZE_BYTE = 2'b00,
        MEM_SIZE_HALF = 2'b01,
        MEM_SIZE_WORD = 2'b10
    } mem_size_t;

    // LSU FSM states
    typedef enum logic [2:0] {
        LSU_IDLE       = 3'b000,
        LSU_ADDR_CALC  = 3'b001,
        LSU_MEM_REQ    = 3'b010,
        LSU_MEM_WAIT   = 3'b011,
        LSU_WRITEBACK  = 3'b100,
        LSU_ERROR      = 3'b101
    } lsu_state_t;

    // Memory response status
    typedef enum logic [1:0] {
        MEM_RESP_OK    = 2'b00,
        MEM_RESP_ERROR = 2'b01,
        MEM_RESP_BUSY  = 2'b10
    } mem_resp_t;

    //==========================================================================
    // Structure Definitions
    //==========================================================================
    
    // LSU request from execution unit
    typedef struct packed {
        logic                   valid;
        mem_op_t                op;
        logic [ADDR_WIDTH-1:0]  base_addr;
        logic [11:0]            offset;
        logic [DATA_WIDTH-1:0]  store_data;
        logic [2:0]             funct3;
        logic [4:0]             rd;          // Destination register (for loads)
    } lsu_req_t;

    // LSU response to execution unit
    typedef struct packed {
        logic                   valid;
        logic                   ready;
        logic [DATA_WIDTH-1:0]  load_data;
        logic [4:0]             rd;
        logic                   exception;
        logic [3:0]             exception_code;
    } lsu_resp_t;

    // Memory interface request
    typedef struct packed {
        logic                   valid;
        logic                   we;          // Write enable
        logic [ADDR_WIDTH-1:0]  addr;
        logic [DATA_WIDTH-1:0]  wdata;
        logic [3:0]             be;          // Byte enable
    } mem_req_t;

    // Memory interface response
    typedef struct packed {
        logic                   valid;
        logic [DATA_WIDTH-1:0]  rdata;
        mem_resp_t              status;
    } mem_resp_struct_t;

    // Load buffer entry
    typedef struct packed {
        logic                   valid;
        logic                   pending;
        logic [ADDR_WIDTH-1:0]  addr;
        logic [2:0]             funct3;
        logic [4:0]             rd;
    } load_buffer_entry_t;

    // Store buffer entry
    typedef struct packed {
        logic                   valid;
        logic                   committed;
        logic [ADDR_WIDTH-1:0]  addr;
        logic [DATA_WIDTH-1:0]  data;
        logic [3:0]             be;
    } store_buffer_entry_t;

    //==========================================================================
    // Exception Codes (RISC-V Privileged Spec)
    //==========================================================================
    parameter [3:0] EXC_LOAD_ADDR_MISALIGN  = 4'd4;
    parameter [3:0] EXC_LOAD_ACCESS_FAULT   = 4'd5;
    parameter [3:0] EXC_STORE_ADDR_MISALIGN = 4'd6;
    parameter [3:0] EXC_STORE_ACCESS_FAULT  = 4'd7;

    //==========================================================================
    // Utility Functions
    //==========================================================================
    
    // Check address alignment based on access size
    function automatic logic check_alignment(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [1:0] size
    );
        case (size)
            MEM_SIZE_BYTE: return 1'b1;                    // Byte always aligned
            MEM_SIZE_HALF: return (addr[0] == 1'b0);      // Halfword: 2-byte aligned
            MEM_SIZE_WORD: return (addr[1:0] == 2'b00);   // Word: 4-byte aligned
            default:       return 1'b0;
        endcase
    endfunction

    // Generate byte enable based on address and size
    function automatic logic [3:0] gen_byte_enable(
        input logic [1:0] addr_lsb,
        input logic [1:0] size
    );
        case (size)
            MEM_SIZE_BYTE: return 4'b0001 << addr_lsb;
            MEM_SIZE_HALF: return 4'b0011 << addr_lsb;
            MEM_SIZE_WORD: return 4'b1111;
            default:       return 4'b0000;
        endcase
    endfunction

    // Sign extend loaded data based on access size
    function automatic logic [DATA_WIDTH-1:0] sign_extend_data(
        input logic [DATA_WIDTH-1:0] data,
        input logic [1:0] addr_lsb,
        input logic [2:0] funct3
    );
        logic [7:0]  byte_data;
        logic [15:0] half_data;
        
        // Extract byte based on address LSBs
        case (addr_lsb)
            2'b00: byte_data = data[7:0];
            2'b01: byte_data = data[15:8];
            2'b10: byte_data = data[23:16];
            2'b11: byte_data = data[31:24];
        endcase
        
        // Extract halfword based on address LSB[1]
        case (addr_lsb[1])
            1'b0: half_data = data[15:0];
            1'b1: half_data = data[31:16];
        endcase
        
        case (funct3)
            FUNCT3_LB:  return {{24{byte_data[7]}}, byte_data};
            FUNCT3_LH:  return {{16{half_data[15]}}, half_data};
            FUNCT3_LW:  return data;
            FUNCT3_LBU: return {24'b0, byte_data};
            FUNCT3_LHU: return {16'b0, half_data};
            default:    return data;
        endcase
    endfunction

endpackage

`endif // LSU_PKG_SV
