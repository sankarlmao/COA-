//==============================================================================
// File: load_buffer.sv
// Description: Load Buffer for RISC-V Load Store Unit
//              Holds pending load requests and manages load completion
//              Supports out-of-order load completion
// Author: COA Project
// Date: March 2026
//==============================================================================

`include "lsu_pkg.sv"

module load_buffer
    import lsu_pkg::*;
#(
    parameter DEPTH = BUFFER_DEPTH
)(
    input  logic                    clk,
    input  logic                    rst_n,
    
    // Allocation interface (from LSU controller)
    input  logic                    alloc_valid_i,
    input  logic [ADDR_WIDTH-1:0]   alloc_addr_i,
    input  logic [2:0]              alloc_funct3_i,
    input  logic [4:0]              alloc_rd_i,
    output logic                    alloc_ready_o,
    output logic [$clog2(DEPTH)-1:0] alloc_idx_o,
    
    // Completion interface (from memory)
    input  logic                    complete_valid_i,
    input  logic [$clog2(DEPTH)-1:0] complete_idx_i,
    input  logic [DATA_WIDTH-1:0]   complete_data_i,
    
    // Writeback interface (to register file)
    output logic                    wb_valid_o,
    output logic [DATA_WIDTH-1:0]   wb_data_o,
    output logic [4:0]              wb_rd_o,
    input  logic                    wb_ready_i,
    
    // Store-to-load forwarding check interface
    input  logic [ADDR_WIDTH-1:0]   stl_check_addr_i,
    output logic                    stl_hit_o,
    
    // Flush interface
    input  logic                    flush_i,
    
    // Status
    output logic                    empty_o,
    output logic                    full_o
);

    //==========================================================================
    // Internal Signals - Using separate arrays instead of struct array
    //==========================================================================
    logic                   buf_valid   [DEPTH];
    logic                   buf_pending [DEPTH];
    logic [ADDR_WIDTH-1:0]  buf_addr    [DEPTH];
    logic [2:0]             buf_funct3  [DEPTH];
    logic [4:0]             buf_rd      [DEPTH];
    logic [DATA_WIDTH-1:0]  buf_data    [DEPTH];
    
    logic [$clog2(DEPTH)-1:0] head_ptr, tail_ptr;
    logic [$clog2(DEPTH):0] count;
    
    // Find first free entry
    logic [$clog2(DEPTH)-1:0] free_idx;
    logic free_found;
    
    //==========================================================================
    // Buffer Status Logic
    //==========================================================================
    assign empty_o = (count == 0);
    assign full_o  = (count == DEPTH);
    assign alloc_ready_o = !full_o && !flush_i;

    //==========================================================================
    // Free Entry Search
    //==========================================================================
    always_comb begin
        free_found = 1'b0;
        free_idx = '0;
        for (int i = 0; i < DEPTH; i++) begin
            if (!buf_valid[i] && !free_found) begin
                free_found = 1'b1;
                free_idx = i[$clog2(DEPTH)-1:0];
            end
        end
    end
    
    assign alloc_idx_o = free_idx;

    //==========================================================================
    // Buffer Entry Management
    //==========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < DEPTH; i++) begin
                buf_valid[i]   <= 1'b0;
                buf_pending[i] <= 1'b0;
                buf_addr[i]    <= '0;
                buf_funct3[i]  <= '0;
                buf_rd[i]      <= '0;
                buf_data[i]    <= '0;
            end
            head_ptr <= '0;
            tail_ptr <= '0;
            count <= '0;
        end else if (flush_i) begin
            // Flush all entries
            for (int i = 0; i < DEPTH; i++) begin
                buf_valid[i] <= 1'b0;
            end
            head_ptr <= '0;
            tail_ptr <= '0;
            count <= '0;
        end else begin
            // Allocation of new load request
            if (alloc_valid_i && alloc_ready_o) begin
                buf_valid[free_idx]   <= 1'b1;
                buf_pending[free_idx] <= 1'b1;
                buf_addr[free_idx]    <= alloc_addr_i;
                buf_funct3[free_idx]  <= alloc_funct3_i;
                buf_rd[free_idx]      <= alloc_rd_i;
                count <= count + 1;
            end
            
            // Completion from memory
            if (complete_valid_i && buf_valid[complete_idx_i]) begin
                buf_pending[complete_idx_i] <= 1'b0;
                buf_data[complete_idx_i] <= complete_data_i;
            end
            
            // Writeback to register file
            if (wb_valid_o && wb_ready_i) begin
                buf_valid[head_ptr] <= 1'b0;
                head_ptr <= head_ptr + 1;
                count <= count - 1;
            end
        end
    end

    //==========================================================================
    // Writeback Logic (In-Order Completion)
    //==========================================================================
    // Get current head entry fields
    logic        head_valid;
    logic        head_pending;
    logic [1:0]  head_addr_lsb;
    logic [2:0]  head_funct3;
    logic [4:0]  head_rd;
    logic [DATA_WIDTH-1:0] head_data;
    
    assign head_valid    = buf_valid[head_ptr];
    assign head_pending  = buf_pending[head_ptr];
    assign head_addr_lsb = buf_addr[head_ptr][1:0];
    assign head_funct3   = buf_funct3[head_ptr];
    assign head_rd       = buf_rd[head_ptr];
    assign head_data     = buf_data[head_ptr];
    
    assign wb_valid_o = head_valid && !head_pending;
    assign wb_rd_o    = head_rd;
    
    // Sign extension logic
    logic [7:0]  wb_byte_data;
    logic [15:0] wb_half_data;
    
    // Extract byte based on address LSBs
    always_comb begin
        case (head_addr_lsb)
            2'b00: wb_byte_data = head_data[7:0];
            2'b01: wb_byte_data = head_data[15:8];
            2'b10: wb_byte_data = head_data[23:16];
            2'b11: wb_byte_data = head_data[31:24];
        endcase
    end
    
    // Extract halfword based on address LSB[1]
    always_comb begin
        case (head_addr_lsb[1])
            1'b0: wb_half_data = head_data[15:0];
            1'b1: wb_half_data = head_data[31:16];
        endcase
    end
    
    // Sign/zero extend based on funct3
    always_comb begin
        case (head_funct3)
            FUNCT3_LB:  wb_data_o = {{24{wb_byte_data[7]}}, wb_byte_data};
            FUNCT3_LH:  wb_data_o = {{16{wb_half_data[15]}}, wb_half_data};
            FUNCT3_LW:  wb_data_o = head_data;
            FUNCT3_LBU: wb_data_o = {24'b0, wb_byte_data};
            FUNCT3_LHU: wb_data_o = {16'b0, wb_half_data};
            default:    wb_data_o = head_data;
        endcase
    end

    //==========================================================================
    // Store-to-Load Forwarding Check
    // Check if any pending load matches the store address
    //==========================================================================
    always_comb begin
        stl_hit_o = 1'b0;
        for (int i = 0; i < DEPTH; i++) begin
            if (buf_valid[i] && buf_pending[i] &&
                buf_addr[i][ADDR_WIDTH-1:2] == stl_check_addr_i[ADDR_WIDTH-1:2]) begin
                stl_hit_o = 1'b1;
            end
        end
    end

endmodule
