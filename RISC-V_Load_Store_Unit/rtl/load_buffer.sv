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
    // Internal Signals
    //==========================================================================
    load_buffer_entry_t buffer [DEPTH];
    logic [DATA_WIDTH-1:0] data_buffer [DEPTH];
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
            if (!buffer[i].valid && !free_found) begin
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
                buffer[i] <= '0;
                data_buffer[i] <= '0;
            end
            head_ptr <= '0;
            tail_ptr <= '0;
            count <= '0;
        end else if (flush_i) begin
            // Flush all entries
            for (int i = 0; i < DEPTH; i++) begin
                buffer[i] <= '0;
            end
            head_ptr <= '0;
            tail_ptr <= '0;
            count <= '0;
        end else begin
            // Allocation of new load request
            if (alloc_valid_i && alloc_ready_o) begin
                buffer[free_idx].valid   <= 1'b1;
                buffer[free_idx].pending <= 1'b1;
                buffer[free_idx].addr    <= alloc_addr_i;
                buffer[free_idx].funct3  <= alloc_funct3_i;
                buffer[free_idx].rd      <= alloc_rd_i;
                count <= count + 1;
            end
            
            // Completion from memory
            if (complete_valid_i && buffer[complete_idx_i].valid) begin
                buffer[complete_idx_i].pending <= 1'b0;
                data_buffer[complete_idx_i] <= complete_data_i;
            end
            
            // Writeback to register file
            if (wb_valid_o && wb_ready_i) begin
                buffer[head_ptr].valid <= 1'b0;
                head_ptr <= head_ptr + 1;
                count <= count - 1;
            end
        end
    end

    //==========================================================================
    // Writeback Logic (In-Order Completion)
    //==========================================================================
    assign wb_valid_o = buffer[head_ptr].valid && !buffer[head_ptr].pending;
    assign wb_data_o  = sign_extend_data(
        data_buffer[head_ptr],
        buffer[head_ptr].addr[1:0],
        buffer[head_ptr].funct3
    );
    assign wb_rd_o    = buffer[head_ptr].rd;

    //==========================================================================
    // Store-to-Load Forwarding Check
    // Check if any pending load matches the store address
    //==========================================================================
    always_comb begin
        stl_hit_o = 1'b0;
        for (int i = 0; i < DEPTH; i++) begin
            if (buffer[i].valid && buffer[i].pending &&
                buffer[i].addr[ADDR_WIDTH-1:2] == stl_check_addr_i[ADDR_WIDTH-1:2]) begin
                stl_hit_o = 1'b1;
            end
        end
    end

endmodule
