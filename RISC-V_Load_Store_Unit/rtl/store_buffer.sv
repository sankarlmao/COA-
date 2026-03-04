//==============================================================================
// File: store_buffer.sv
// Description: Store Buffer for RISC-V Load Store Unit
//              Holds pending store requests before committing to memory
//              Supports store-to-load forwarding
// Author: COA Project
// Date: March 2026
//==============================================================================

`include "lsu_pkg.sv"

module store_buffer
    import lsu_pkg::*;
#(
    parameter DEPTH = BUFFER_DEPTH
)(
    input  logic                    clk,
    input  logic                    rst_n,
    
    // Allocation interface (from LSU controller)
    input  logic                    alloc_valid_i,
    input  logic [ADDR_WIDTH-1:0]   alloc_addr_i,
    input  logic [DATA_WIDTH-1:0]   alloc_data_i,
    input  logic [3:0]              alloc_be_i,
    output logic                    alloc_ready_o,
    
    // Commit interface (from ROB/commit stage)
    input  logic                    commit_i,
    
    // Memory write interface
    output logic                    mem_req_valid_o,
    output logic [ADDR_WIDTH-1:0]   mem_req_addr_o,
    output logic [DATA_WIDTH-1:0]   mem_req_data_o,
    output logic [3:0]              mem_req_be_o,
    input  logic                    mem_req_ready_i,
    
    // Store-to-load forwarding interface
    input  logic                    fwd_check_valid_i,
    input  logic [ADDR_WIDTH-1:0]   fwd_check_addr_i,
    input  logic [3:0]              fwd_check_be_i,
    output logic                    fwd_hit_o,
    output logic                    fwd_hit_full_o,  // Full forward possible
    output logic [DATA_WIDTH-1:0]   fwd_data_o,
    
    // Flush interface
    input  logic                    flush_i,
    
    // Status
    output logic                    empty_o,
    output logic                    full_o
);

    //==========================================================================
    // Internal Signals - Using separate arrays instead of struct array
    //==========================================================================
    logic                   buf_valid     [DEPTH];
    logic                   buf_committed [DEPTH];
    logic [ADDR_WIDTH-1:0]  buf_addr      [DEPTH];
    logic [DATA_WIDTH-1:0]  buf_data      [DEPTH];
    logic [3:0]             buf_be        [DEPTH];
    
    logic [$clog2(DEPTH)-1:0] head_ptr, tail_ptr;
    logic [$clog2(DEPTH):0] count;
    logic [$clog2(DEPTH):0] committed_count;

    //==========================================================================
    // Buffer Status Logic
    //==========================================================================
    assign empty_o = (count == 0);
    assign full_o  = (count == DEPTH);
    assign alloc_ready_o = !full_o && !flush_i;

    //==========================================================================
    // Buffer Entry Management
    //==========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < DEPTH; i++) begin
                buf_valid[i]     <= 1'b0;
                buf_committed[i] <= 1'b0;
                buf_addr[i]      <= '0;
                buf_data[i]      <= '0;
                buf_be[i]        <= '0;
            end
            head_ptr <= '0;
            tail_ptr <= '0;
            count <= '0;
            committed_count <= '0;
        end else if (flush_i) begin
            // Flush uncommitted entries only
            for (int i = 0; i < DEPTH; i++) begin
                if (!buf_committed[i]) begin
                    buf_valid[i] <= 1'b0;
                end
            end
            // Reset tail pointer but keep committed entries
            tail_ptr <= head_ptr + committed_count[$clog2(DEPTH)-1:0];
            count <= committed_count;
        end else begin
            // Allocation of new store request
            if (alloc_valid_i && alloc_ready_o) begin
                buf_valid[tail_ptr]     <= 1'b1;
                buf_committed[tail_ptr] <= 1'b0;
                buf_addr[tail_ptr]      <= alloc_addr_i;
                buf_data[tail_ptr]      <= alloc_data_i;
                buf_be[tail_ptr]        <= alloc_be_i;
                tail_ptr <= tail_ptr + 1;
                count <= count + 1;
            end
            
            // Commit oldest uncommitted store
            if (commit_i && count > committed_count) begin
                buf_committed[head_ptr + committed_count[$clog2(DEPTH)-1:0]] <= 1'b1;
                committed_count <= committed_count + 1;
            end
            
            // Dequeue committed store after memory write
            if (mem_req_valid_o && mem_req_ready_i) begin
                buf_valid[head_ptr] <= 1'b0;
                buf_committed[head_ptr] <= 1'b0;
                head_ptr <= head_ptr + 1;
                count <= count - 1;
                committed_count <= committed_count - 1;
            end
        end
    end

    //==========================================================================
    // Memory Write Request (FIFO Order for Committed Stores)
    //==========================================================================
    assign mem_req_valid_o = buf_valid[head_ptr] && buf_committed[head_ptr];
    assign mem_req_addr_o  = buf_addr[head_ptr];
    assign mem_req_data_o  = buf_data[head_ptr];
    assign mem_req_be_o    = buf_be[head_ptr];

    //==========================================================================
    // Store-to-Load Forwarding Logic
    // Search from newest to oldest for address match
    //==========================================================================
    always_comb begin
        fwd_hit_o = 1'b0;
        fwd_hit_full_o = 1'b0;
        fwd_data_o = '0;
        
        if (fwd_check_valid_i) begin
            // Search from newest entry to oldest
            for (int i = DEPTH-1; i >= 0; i--) begin
                logic [$clog2(DEPTH)-1:0] idx;
                idx = (tail_ptr - 1 - i[$clog2(DEPTH)-1:0]);
                
                if (buf_valid[idx] &&
                    buf_addr[idx][ADDR_WIDTH-1:2] == fwd_check_addr_i[ADDR_WIDTH-1:2]) begin
                    
                    fwd_hit_o = 1'b1;
                    
                    // Check if store covers all requested bytes
                    if ((buf_be[idx] & fwd_check_be_i) == fwd_check_be_i) begin
                        fwd_hit_full_o = 1'b1;
                        fwd_data_o = buf_data[idx];
                    end
                end
            end
        end
    end

endmodule
