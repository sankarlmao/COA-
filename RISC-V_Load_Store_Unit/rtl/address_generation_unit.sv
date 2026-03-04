//==============================================================================
// File: address_generation_unit.sv
// Description: Address Generation Unit (AGU) for RISC-V Load Store Unit
//              Computes effective address from base + offset
//              Performs alignment checking and generates exceptions
// Author: COA Project
// Date: March 2026
//==============================================================================

`include "lsu_pkg.sv"

module address_generation_unit
    import lsu_pkg::*;
(
    input  logic                    clk,
    input  logic                    rst_n,
    
    // Input: Base address and offset
    input  logic                    valid_i,
    input  logic [ADDR_WIDTH-1:0]   base_addr_i,
    input  logic [11:0]             offset_i,
    input  logic [2:0]              funct3_i,
    input  mem_op_t                 mem_op_i,
    
    // Output: Computed effective address
    output logic                    valid_o,
    output logic [ADDR_WIDTH-1:0]   eff_addr_o,
    output logic                    misaligned_o,
    output logic [3:0]              byte_enable_o,
    output mem_size_t               mem_size_o
);

    //==========================================================================
    // Internal Signals
    //==========================================================================
    logic [ADDR_WIDTH-1:0]  eff_addr;
    logic [11:0]            sign_ext_offset;
    mem_size_t              mem_size;
    logic                   is_aligned;

    //==========================================================================
    // Address Calculation Logic
    // Effective Address = Base Address + Sign-Extended Offset
    //==========================================================================
    
    // Sign extend the 12-bit offset
    assign sign_ext_offset = offset_i;
    
    // Compute effective address (base + sign-extended offset)
    assign eff_addr = base_addr_i + {{(ADDR_WIDTH-12){sign_ext_offset[11]}}, sign_ext_offset};

    //==========================================================================
    // Memory Size Decoding from funct3
    //==========================================================================
    always_comb begin
        case (funct3_i[1:0])
            2'b00:   mem_size = MEM_SIZE_BYTE;
            2'b01:   mem_size = MEM_SIZE_HALF;
            2'b10:   mem_size = MEM_SIZE_WORD;
            default: mem_size = MEM_SIZE_BYTE;
        endcase
    end

    //==========================================================================
    // Alignment Check
    //==========================================================================
    assign is_aligned = check_alignment(eff_addr, mem_size);

    //==========================================================================
    // Byte Enable Generation
    //==========================================================================
    assign byte_enable_o = gen_byte_enable(eff_addr[1:0], mem_size);

    //==========================================================================
    // Output Registration (Pipeline Stage)
    //==========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_o      <= 1'b0;
            eff_addr_o   <= '0;
            misaligned_o <= 1'b0;
            mem_size_o   <= MEM_SIZE_BYTE;
        end else begin
            valid_o      <= valid_i;
            eff_addr_o   <= eff_addr;
            misaligned_o <= valid_i && !is_aligned;
            mem_size_o   <= mem_size;
        end
    end

endmodule
