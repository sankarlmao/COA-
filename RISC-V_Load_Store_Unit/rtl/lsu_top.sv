//==============================================================================
// File: lsu_top.sv
// Description: Top-Level Load Store Unit for RISC-V Processor
//              Integrates AGU, Load Buffer, Store Buffer, and Memory Controller
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
    // Internal Signals
    //==========================================================================
    
    // AGU signals
    logic                    agu_valid;
    logic [ADDR_WIDTH-1:0]   agu_eff_addr;
    logic                    agu_misaligned;
    logic [3:0]              agu_byte_enable;
    mem_size_t               agu_mem_size;
    
    // Load Buffer signals
    logic                    lb_alloc_valid;
    logic                    lb_alloc_ready;
    logic [$clog2(BUFFER_DEPTH)-1:0] lb_alloc_idx;
    logic                    lb_wb_valid;
    logic [DATA_WIDTH-1:0]   lb_wb_data;
    logic [4:0]              lb_wb_rd;
    logic                    lb_empty;
    logic                    lb_full;
    
    // Store Buffer signals
    logic                    sb_alloc_valid;
    logic                    sb_alloc_ready;
    logic                    sb_mem_req_valid;
    logic [ADDR_WIDTH-1:0]   sb_mem_req_addr;
    logic [DATA_WIDTH-1:0]   sb_mem_req_data;
    logic [3:0]              sb_mem_req_be;
    logic                    sb_fwd_hit;
    logic                    sb_fwd_hit_full;
    logic [DATA_WIDTH-1:0]   sb_fwd_data;
    logic                    sb_empty;
    logic                    sb_full;
    
    // Memory Controller signals
    logic                    mc_load_req_valid;
    logic                    mc_load_req_ready;
    logic                    mc_load_resp_valid;
    logic [$clog2(BUFFER_DEPTH)-1:0] mc_load_resp_idx;
    logic [DATA_WIDTH-1:0]   mc_load_resp_data;
    logic                    mc_store_req_ready;
    
    // FSM state
    lsu_state_t              state, next_state;
    
    // Pipeline registers
    logic                    req_is_store_r;
    logic [ADDR_WIDTH-1:0]   req_addr_r;
    logic [DATA_WIDTH-1:0]   req_wdata_r;
    logic [2:0]              req_funct3_r;
    logic [4:0]              req_rd_r;
    logic [3:0]              req_be_r;

    //==========================================================================
    // Address Generation Unit Instance
    //==========================================================================
    address_generation_unit u_agu (
        .clk            (clk),
        .rst_n          (rst_n),
        .valid_i        (cpu_req_valid_i && cpu_req_ready_o),
        .base_addr_i    (cpu_req_base_addr_i),
        .offset_i       (cpu_req_offset_i),
        .funct3_i       (cpu_req_funct3_i),
        .mem_op_i       (cpu_req_we_i ? MEM_OP_STORE : MEM_OP_LOAD),
        .valid_o        (agu_valid),
        .eff_addr_o     (agu_eff_addr),
        .misaligned_o   (agu_misaligned),
        .byte_enable_o  (agu_byte_enable),
        .mem_size_o     (agu_mem_size)
    );

    //==========================================================================
    // Load Buffer Instance
    //==========================================================================
    load_buffer #(
        .DEPTH(BUFFER_DEPTH)
    ) u_load_buffer (
        .clk                (clk),
        .rst_n              (rst_n),
        .alloc_valid_i      (lb_alloc_valid),
        .alloc_addr_i       (req_addr_r),
        .alloc_funct3_i     (req_funct3_r),
        .alloc_rd_i         (req_rd_r),
        .alloc_ready_o      (lb_alloc_ready),
        .alloc_idx_o        (lb_alloc_idx),
        .complete_valid_i   (mc_load_resp_valid),
        .complete_idx_i     (mc_load_resp_idx),
        .complete_data_i    (mc_load_resp_data),
        .wb_valid_o         (lb_wb_valid),
        .wb_data_o          (lb_wb_data),
        .wb_rd_o            (lb_wb_rd),
        .wb_ready_i         (cpu_resp_ready_i),
        .stl_check_addr_i   (req_addr_r),
        .stl_hit_o          (),   // Not used in simple implementation
        .flush_i            (flush_i),
        .empty_o            (lb_empty),
        .full_o             (lb_full)
    );

    //==========================================================================
    // Store Buffer Instance
    //==========================================================================
    store_buffer #(
        .DEPTH(BUFFER_DEPTH)
    ) u_store_buffer (
        .clk                (clk),
        .rst_n              (rst_n),
        .alloc_valid_i      (sb_alloc_valid),
        .alloc_addr_i       (req_addr_r),
        .alloc_data_i       (req_wdata_r),
        .alloc_be_i         (req_be_r),
        .alloc_ready_o      (sb_alloc_ready),
        .commit_i           (commit_i),
        .mem_req_valid_o    (sb_mem_req_valid),
        .mem_req_addr_o     (sb_mem_req_addr),
        .mem_req_data_o     (sb_mem_req_data),
        .mem_req_be_o       (sb_mem_req_be),
        .mem_req_ready_i    (mc_store_req_ready),
        .fwd_check_valid_i  (lb_alloc_valid),
        .fwd_check_addr_i   (req_addr_r),
        .fwd_check_be_i     (req_be_r),
        .fwd_hit_o          (sb_fwd_hit),
        .fwd_hit_full_o     (sb_fwd_hit_full),
        .fwd_data_o         (sb_fwd_data),
        .flush_i            (flush_i),
        .empty_o            (sb_empty),
        .full_o             (sb_full)
    );

    //==========================================================================
    // Memory Controller Instance
    //==========================================================================
    memory_controller u_mem_ctrl (
        .clk                (clk),
        .rst_n              (rst_n),
        // Load interface
        .load_req_valid_i   (mc_load_req_valid),
        .load_req_addr_i    (req_addr_r),
        .load_req_be_i      (req_be_r),
        .load_req_idx_i     (lb_alloc_idx),
        .load_req_ready_o   (mc_load_req_ready),
        .load_resp_valid_o  (mc_load_resp_valid),
        .load_resp_idx_o    (mc_load_resp_idx),
        .load_resp_data_o   (mc_load_resp_data),
        .load_resp_error_o  (),
        // Store interface
        .store_req_valid_i  (sb_mem_req_valid),
        .store_req_addr_i   (sb_mem_req_addr),
        .store_req_data_i   (sb_mem_req_data),
        .store_req_be_i     (sb_mem_req_be),
        .store_req_ready_o  (mc_store_req_ready),
        .store_resp_valid_o (),
        .store_resp_error_o (),
        // Memory interface
        .mem_req_valid_o    (mem_req_valid_o),
        .mem_req_we_o       (mem_req_we_o),
        .mem_req_addr_o     (mem_req_addr_o),
        .mem_req_wdata_o    (mem_req_wdata_o),
        .mem_req_be_o       (mem_req_be_o),
        .mem_req_ready_i    (mem_req_ready_i),
        .mem_resp_valid_i   (mem_resp_valid_i),
        .mem_resp_rdata_i   (mem_resp_rdata_i),
        .mem_resp_error_i   (mem_resp_error_i)
    );

    //==========================================================================
    // LSU Control FSM
    //==========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= LSU_IDLE;
        end else if (flush_i) begin
            state <= LSU_IDLE;
        end else begin
            state <= next_state;
        end
    end

    always_comb begin
        next_state = state;
        
        case (state)
            LSU_IDLE: begin
                if (cpu_req_valid_i && cpu_req_ready_o) begin
                    next_state = LSU_ADDR_CALC;
                end
            end
            
            LSU_ADDR_CALC: begin
                if (agu_valid) begin
                    if (agu_misaligned) begin
                        next_state = LSU_ERROR;
                    end else begin
                        next_state = LSU_MEM_REQ;
                    end
                end
            end
            
            LSU_MEM_REQ: begin
                if (req_is_store_r) begin
                    if (sb_alloc_ready) begin
                        next_state = LSU_IDLE;
                    end
                end else begin
                    if (lb_alloc_ready) begin
                        next_state = LSU_IDLE;
                    end
                end
            end
            
            LSU_ERROR: begin
                if (cpu_resp_ready_i) begin
                    next_state = LSU_IDLE;
                end
            end
            
            default: next_state = LSU_IDLE;
        endcase
    end

    //==========================================================================
    // Pipeline Registers
    //==========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            req_is_store_r <= 1'b0;
            req_addr_r     <= '0;
            req_wdata_r    <= '0;
            req_funct3_r   <= '0;
            req_rd_r       <= '0;
            req_be_r       <= '0;
        end else if (cpu_req_valid_i && cpu_req_ready_o) begin
            req_is_store_r <= cpu_req_we_i;
            req_wdata_r    <= cpu_req_wdata_i;
            req_funct3_r   <= cpu_req_funct3_i;
            req_rd_r       <= cpu_req_rd_i;
        end else if (agu_valid) begin
            req_addr_r     <= agu_eff_addr;
            req_be_r       <= agu_byte_enable;
        end
    end

    //==========================================================================
    // Control Signal Generation
    //==========================================================================
    
    // CPU request ready when idle and buffers not full
    assign cpu_req_ready_o = (state == LSU_IDLE) && !lb_full && !sb_full;
    
    // Load buffer allocation
    assign lb_alloc_valid = (state == LSU_MEM_REQ) && !req_is_store_r && !sb_fwd_hit_full;
    
    // Store buffer allocation
    assign sb_alloc_valid = (state == LSU_MEM_REQ) && req_is_store_r;
    
    // Memory controller load request
    assign mc_load_req_valid = lb_alloc_valid && lb_alloc_ready;

    //==========================================================================
    // CPU Response Generation
    //==========================================================================
    always_comb begin
        cpu_resp_valid_o   = 1'b0;
        cpu_resp_rdata_o   = '0;
        cpu_resp_rd_o      = '0;
        cpu_resp_error_o   = 1'b0;
        cpu_resp_exc_code_o = '0;
        
        if (state == LSU_ERROR) begin
            // Misalignment exception
            cpu_resp_valid_o    = 1'b1;
            cpu_resp_error_o    = 1'b1;
            cpu_resp_rd_o       = req_rd_r;
            cpu_resp_exc_code_o = req_is_store_r ? EXC_STORE_ADDR_MISALIGN : 
                                                   EXC_LOAD_ADDR_MISALIGN;
        end else if (lb_wb_valid) begin
            // Load writeback
            cpu_resp_valid_o = 1'b1;
            cpu_resp_rdata_o = lb_wb_data;
            cpu_resp_rd_o    = lb_wb_rd;
        end else if (sb_fwd_hit_full && (state == LSU_MEM_REQ) && !req_is_store_r) begin
            // Store-to-load forwarding
            cpu_resp_valid_o = 1'b1;
            cpu_resp_rdata_o = sign_extend_data(sb_fwd_data, req_addr_r[1:0], req_funct3_r);
            cpu_resp_rd_o    = req_rd_r;
        end
    end

    //==========================================================================
    // Status Outputs
    //==========================================================================
    assign lsu_busy_o          = (state != LSU_IDLE);
    assign load_buffer_full_o  = lb_full;
    assign store_buffer_full_o = sb_full;

endmodule
