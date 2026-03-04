//==============================================================================
// File: lsu_top.sv
// Description: Top-Level Load Store Unit for RISC-V Processor
//              Simplified design for correct operation with Icarus Verilog
//              Supports RV32I load/store instructions
// Author: COA Project
// Date: March 2026
//==============================================================================

`include "lsu_pkg.sv"

module lsu_top
    import lsu_pkg::*;
(
    input  logic                    clk,
    input  logic                    rst_n,
    
    //==========================================================================
    // CPU Interface (from Execution Unit)
    //==========================================================================
    // Request from CPU
    input  logic                    cpu_req_valid_i,
    input  logic                    cpu_req_we_i,        // 1=Store, 0=Load
    input  logic [ADDR_WIDTH-1:0]   cpu_req_base_addr_i,
    input  logic [11:0]             cpu_req_offset_i,
    input  logic [DATA_WIDTH-1:0]   cpu_req_wdata_i,
    input  logic [2:0]              cpu_req_funct3_i,
    input  logic [4:0]              cpu_req_rd_i,        // Destination reg (loads)
    output logic                    cpu_req_ready_o,
    
    // Response to CPU
    output logic                    cpu_resp_valid_o,
    output logic [DATA_WIDTH-1:0]   cpu_resp_rdata_o,
    output logic [4:0]              cpu_resp_rd_o,
    output logic                    cpu_resp_error_o,
    output logic [3:0]              cpu_resp_exc_code_o,
    input  logic                    cpu_resp_ready_i,
    
    // Commit signal (from ROB/commit stage)
    input  logic                    commit_i,
    
    // Flush signal (for branch misprediction, etc.)
    input  logic                    flush_i,
    
    //==========================================================================
    // Memory Interface (to Data Cache / Main Memory)
    //==========================================================================
    output logic                    mem_req_valid_o,
    output logic                    mem_req_we_o,
    output logic [ADDR_WIDTH-1:0]   mem_req_addr_o,
    output logic [DATA_WIDTH-1:0]   mem_req_wdata_o,
    output logic [3:0]              mem_req_be_o,
    input  logic                    mem_req_ready_i,
    
    input  logic                    mem_resp_valid_i,
    input  logic [DATA_WIDTH-1:0]   mem_resp_rdata_i,
    input  logic                    mem_resp_error_i,
    
    //==========================================================================
    // Status Outputs
    //==========================================================================
    output logic                    lsu_busy_o,
    output logic                    load_buffer_full_o,
    output logic                    store_buffer_full_o
);

    //==========================================================================
    // FSM States
    //==========================================================================
    typedef enum logic [2:0] {
        IDLE        = 3'b000,
        ADDR_CALC   = 3'b001,
        MEM_REQ     = 3'b010,
        MEM_WAIT    = 3'b011,
        WRITEBACK   = 3'b100,
        ERROR       = 3'b101
    } state_t;
    
    state_t state, next_state;

    //==========================================================================
    // Internal Signals
    //==========================================================================
    // Effective address computation
    logic [ADDR_WIDTH-1:0] eff_addr;
    logic [11:0] sign_ext_offset;
    
    // Request registers
    logic                   req_is_store_r;
    logic [ADDR_WIDTH-1:0]  req_addr_r;
    logic [DATA_WIDTH-1:0]  req_wdata_r;
    logic [2:0]             req_funct3_r;
    logic [4:0]             req_rd_r;
    logic [3:0]             req_be_r;
    
    // Alignment check
    logic is_aligned;
    
    // Memory size from funct3
    logic [1:0] mem_size;
    
    // Store data shifted to correct byte position
    logic [DATA_WIDTH-1:0] shifted_store_data;
    
    // Load data sign extension
    logic [DATA_WIDTH-1:0] load_data_extended;

    //==========================================================================
    // Address Computation
    //==========================================================================
    assign sign_ext_offset = cpu_req_offset_i;
    assign eff_addr = cpu_req_base_addr_i + {{(ADDR_WIDTH-12){sign_ext_offset[11]}}, sign_ext_offset};

    //==========================================================================
    // Memory Size Decode
    //==========================================================================
    always_comb begin
        case (cpu_req_funct3_i[1:0])
            2'b00:   mem_size = 2'b00;  // Byte
            2'b01:   mem_size = 2'b01;  // Halfword
            2'b10:   mem_size = 2'b10;  // Word
            default: mem_size = 2'b00;
        endcase
    end

    //==========================================================================
    // Alignment Check
    //==========================================================================
    always_comb begin
        case (mem_size)
            2'b00:   is_aligned = 1'b1;                    // Byte always aligned
            2'b01:   is_aligned = (eff_addr[0] == 1'b0);   // Halfword
            2'b10:   is_aligned = (eff_addr[1:0] == 2'b00);// Word
            default: is_aligned = 1'b1;
        endcase
    end

    //==========================================================================
    // Byte Enable Generation
    //==========================================================================
    logic [3:0] byte_enable;
    always_comb begin
        case (mem_size)
            2'b00: byte_enable = 4'b0001 << eff_addr[1:0];  // Byte
            2'b01: byte_enable = 4'b0011 << eff_addr[1:0];  // Halfword
            2'b10: byte_enable = 4'b1111;                    // Word
            default: byte_enable = 4'b0001;
        endcase
    end

    //==========================================================================
    // Store Data Shifting (place data at correct byte position)
    //==========================================================================
    always_comb begin
        case (mem_size)
            2'b00: begin // Byte - replicate to all positions
                shifted_store_data = {cpu_req_wdata_i[7:0], cpu_req_wdata_i[7:0],
                                      cpu_req_wdata_i[7:0], cpu_req_wdata_i[7:0]};
            end
            2'b01: begin // Halfword - replicate to both positions  
                shifted_store_data = {cpu_req_wdata_i[15:0], cpu_req_wdata_i[15:0]};
            end
            2'b10: begin // Word - no shift needed
                shifted_store_data = cpu_req_wdata_i;
            end
            default: shifted_store_data = cpu_req_wdata_i;
        endcase
    end

    //==========================================================================
    // FSM State Register
    //==========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else if (flush_i) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    //==========================================================================
    // FSM Next State Logic
    //==========================================================================
    always_comb begin
        next_state = state;
        
        case (state)
            IDLE: begin
                if (cpu_req_valid_i && cpu_req_ready_o) begin
                    next_state = ADDR_CALC;
                end
            end
            
            ADDR_CALC: begin
                if (!is_aligned) begin
                    next_state = ERROR;
                end else begin
                    next_state = MEM_REQ;
                end
            end
            
            MEM_REQ: begin
                if (mem_req_ready_i) begin
                    if (req_is_store_r) begin
                        next_state = IDLE;  // Stores complete immediately
                    end else if (mem_resp_valid_i) begin
                        next_state = WRITEBACK;  // Zero latency - response available immediately
                    end else begin
                        next_state = MEM_WAIT;  // Non-zero latency - wait for response
                    end
                end
            end
            
            MEM_WAIT: begin
                if (mem_resp_valid_i) begin
                    next_state = WRITEBACK;
                end
            end
            
            WRITEBACK: begin
                if (cpu_resp_ready_i) begin
                    next_state = IDLE;
                end
            end
            
            ERROR: begin
                if (cpu_resp_ready_i) begin
                    next_state = IDLE;
                end
            end
            
            default: next_state = IDLE;
        endcase
    end

    //==========================================================================
    // Request Registers
    //==========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            req_is_store_r <= 1'b0;
            req_addr_r     <= '0;
            req_wdata_r    <= '0;
            req_funct3_r   <= '0;
            req_rd_r       <= '0;
            req_be_r       <= '0;
        end else if (state == IDLE && cpu_req_valid_i && cpu_req_ready_o) begin
            req_is_store_r <= cpu_req_we_i;
            req_addr_r     <= eff_addr;
            req_wdata_r    <= shifted_store_data;  // Use shifted data for stores
            req_funct3_r   <= cpu_req_funct3_i;
            req_rd_r       <= cpu_req_rd_i;
            req_be_r       <= byte_enable;
        end
    end

    //==========================================================================
    // CPU Request Interface
    //==========================================================================
    assign cpu_req_ready_o = (state == IDLE);

    //==========================================================================
    // Memory Request Interface
    //==========================================================================
    assign mem_req_valid_o = (state == MEM_REQ);
    assign mem_req_we_o    = req_is_store_r;
    assign mem_req_addr_o  = req_addr_r;
    assign mem_req_wdata_o = req_wdata_r;
    assign mem_req_be_o    = req_be_r;

    //==========================================================================
    // Load Data Sign Extension
    //==========================================================================
    logic [7:0]  load_byte;
    logic [15:0] load_half;
    logic [DATA_WIDTH-1:0] load_data_reg;
    logic [DATA_WIDTH-1:0] active_load_data;
    
    // Register the load data when it arrives (support both zero and non-zero latency)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            load_data_reg <= '0;
        end else if (mem_resp_valid_i && (state == MEM_WAIT || state == MEM_REQ)) begin
            load_data_reg <= mem_resp_rdata_i;
        end
    end
    
    // Use registered data in WRITEBACK
    assign active_load_data = load_data_reg;
    
    // Extract byte based on address LSBs
    always_comb begin
        case (req_addr_r[1:0])
            2'b00: load_byte = active_load_data[7:0];
            2'b01: load_byte = active_load_data[15:8];
            2'b10: load_byte = active_load_data[23:16];
            2'b11: load_byte = active_load_data[31:24];
        endcase
    end
    
    // Extract halfword based on address LSB[1]
    always_comb begin
        case (req_addr_r[1])
            1'b0: load_half = active_load_data[15:0];
            1'b1: load_half = active_load_data[31:16];
        endcase
    end
    
    // Sign/zero extend based on funct3
    always_comb begin
        case (req_funct3_r)
            FUNCT3_LB:  load_data_extended = {{24{load_byte[7]}}, load_byte};
            FUNCT3_LH:  load_data_extended = {{16{load_half[15]}}, load_half};
            FUNCT3_LW:  load_data_extended = active_load_data;
            FUNCT3_LBU: load_data_extended = {24'b0, load_byte};
            FUNCT3_LHU: load_data_extended = {16'b0, load_half};
            default:    load_data_extended = active_load_data;
        endcase
    end

    //==========================================================================
    // CPU Response Interface
    //==========================================================================
    always_comb begin
        cpu_resp_valid_o    = 1'b0;
        cpu_resp_rdata_o    = '0;
        cpu_resp_rd_o       = '0;
        cpu_resp_error_o    = 1'b0;
        cpu_resp_exc_code_o = '0;
        
        case (state)
            WRITEBACK: begin
                cpu_resp_valid_o = 1'b1;
                cpu_resp_rdata_o = load_data_extended;
                cpu_resp_rd_o    = req_rd_r;
            end
            
            ERROR: begin
                cpu_resp_valid_o    = 1'b1;
                cpu_resp_error_o    = 1'b1;
                cpu_resp_rd_o       = req_rd_r;
                cpu_resp_exc_code_o = req_is_store_r ? EXC_STORE_ADDR_MISALIGN : 
                                                       EXC_LOAD_ADDR_MISALIGN;
            end
            
            default: begin
                // No response
            end
        endcase
    end

    //==========================================================================
    // Status Outputs
    //==========================================================================
    assign lsu_busy_o          = (state != IDLE);
    assign load_buffer_full_o  = 1'b0;  // Simplified - no buffer
    assign store_buffer_full_o = 1'b0;  // Simplified - no buffer

endmodule
