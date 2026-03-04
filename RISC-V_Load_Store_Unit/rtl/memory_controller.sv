//==============================================================================
// File: memory_controller.sv
// Description: Memory Interface Controller for RISC-V Load Store Unit
//              Handles memory request arbitration and protocol management
//              Supports AXI-like handshake protocol
// Author: COA Project
// Date: March 2026
//==============================================================================

`include "lsu_pkg.sv"

module memory_controller
    import lsu_pkg::*;
(
    input  logic                    clk,
    input  logic                    rst_n,
    
    //==========================================================================
    // Load Interface (from Load Buffer)
    //==========================================================================
    input  logic                    load_req_valid_i,
    input  logic [ADDR_WIDTH-1:0]   load_req_addr_i,
    input  logic [3:0]              load_req_be_i,
    input  logic [$clog2(BUFFER_DEPTH)-1:0] load_req_idx_i,
    output logic                    load_req_ready_o,
    
    output logic                    load_resp_valid_o,
    output logic [$clog2(BUFFER_DEPTH)-1:0] load_resp_idx_o,
    output logic [DATA_WIDTH-1:0]   load_resp_data_o,
    output logic                    load_resp_error_o,
    
    //==========================================================================
    // Store Interface (from Store Buffer)
    //==========================================================================
    input  logic                    store_req_valid_i,
    input  logic [ADDR_WIDTH-1:0]   store_req_addr_i,
    input  logic [DATA_WIDTH-1:0]   store_req_data_i,
    input  logic [3:0]              store_req_be_i,
    output logic                    store_req_ready_o,
    
    output logic                    store_resp_valid_o,
    output logic                    store_resp_error_o,
    
    //==========================================================================
    // Memory Interface (to Data Memory / Cache)
    //==========================================================================
    output logic                    mem_req_valid_o,
    output logic                    mem_req_we_o,
    output logic [ADDR_WIDTH-1:0]   mem_req_addr_o,
    output logic [DATA_WIDTH-1:0]   mem_req_wdata_o,
    output logic [3:0]              mem_req_be_o,
    input  logic                    mem_req_ready_i,
    
    input  logic                    mem_resp_valid_i,
    input  logic [DATA_WIDTH-1:0]   mem_resp_rdata_i,
    input  logic                    mem_resp_error_i
);

    //==========================================================================
    // Internal Types and Signals
    //==========================================================================
    typedef enum logic [1:0] {
        ARB_IDLE,
        ARB_LOAD,
        ARB_STORE
    } arb_state_t;
    
    arb_state_t arb_state, arb_next_state;
    
    // Pending request tracking
    logic pending_load;
    logic pending_store;
    logic [$clog2(BUFFER_DEPTH)-1:0] pending_load_idx;

    //==========================================================================
    // Arbiter FSM - Gives priority to stores to maintain memory ordering
    //==========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            arb_state <= ARB_IDLE;
        end else begin
            arb_state <= arb_next_state;
        end
    end
    
    always_comb begin
        arb_next_state = arb_state;
        
        case (arb_state)
            ARB_IDLE: begin
                if (store_req_valid_i) begin
                    arb_next_state = ARB_STORE;
                end else if (load_req_valid_i) begin
                    arb_next_state = ARB_LOAD;
                end
            end
            
            ARB_LOAD: begin
                if (mem_req_ready_i) begin
                    if (store_req_valid_i) begin
                        arb_next_state = ARB_STORE;
                    end else if (!load_req_valid_i) begin
                        arb_next_state = ARB_IDLE;
                    end
                end
            end
            
            ARB_STORE: begin
                if (mem_req_ready_i) begin
                    if (load_req_valid_i && !store_req_valid_i) begin
                        arb_next_state = ARB_LOAD;
                    end else if (!store_req_valid_i) begin
                        arb_next_state = ARB_IDLE;
                    end
                end
            end
        endcase
    end

    //==========================================================================
    // Memory Request Muxing
    //==========================================================================
    always_comb begin
        mem_req_valid_o = 1'b0;
        mem_req_we_o    = 1'b0;
        mem_req_addr_o  = '0;
        mem_req_wdata_o = '0;
        mem_req_be_o    = '0;
        
        load_req_ready_o  = 1'b0;
        store_req_ready_o = 1'b0;
        
        case (arb_state)
            ARB_LOAD: begin
                mem_req_valid_o   = load_req_valid_i;
                mem_req_we_o      = 1'b0;
                mem_req_addr_o    = load_req_addr_i;
                mem_req_be_o      = load_req_be_i;
                load_req_ready_o  = mem_req_ready_i;
            end
            
            ARB_STORE: begin
                mem_req_valid_o   = store_req_valid_i;
                mem_req_we_o      = 1'b1;
                mem_req_addr_o    = store_req_addr_i;
                mem_req_wdata_o   = store_req_data_i;
                mem_req_be_o      = store_req_be_i;
                store_req_ready_o = mem_req_ready_i;
            end
            
            default: begin
                // IDLE state - no active request
            end
        endcase
    end

    //==========================================================================
    // Pending Request Tracking for Response Routing
    //==========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_load     <= 1'b0;
            pending_store    <= 1'b0;
            pending_load_idx <= '0;
        end else begin
            // Track load request
            if (load_req_valid_i && load_req_ready_o) begin
                pending_load     <= 1'b1;
                pending_load_idx <= load_req_idx_i;
            end else if (mem_resp_valid_i && pending_load) begin
                pending_load <= 1'b0;
            end
            
            // Track store request
            if (store_req_valid_i && store_req_ready_o) begin
                pending_store <= 1'b1;
            end else if (mem_resp_valid_i && pending_store) begin
                pending_store <= 1'b0;
            end
        end
    end

    //==========================================================================
    // Response Routing
    //==========================================================================
    assign load_resp_valid_o  = mem_resp_valid_i && pending_load;
    assign load_resp_idx_o    = pending_load_idx;
    assign load_resp_data_o   = mem_resp_rdata_i;
    assign load_resp_error_o  = mem_resp_error_i && pending_load;
    
    assign store_resp_valid_o = mem_resp_valid_i && pending_store;
    assign store_resp_error_o = mem_resp_error_i && pending_store;

endmodule
