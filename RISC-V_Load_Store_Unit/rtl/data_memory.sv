//==============================================================================
// File: data_memory.sv
// Description: Simple Data Memory Model for RISC-V LSU Simulation
//              Single-cycle latency with configurable delay
//              Supports byte-enable writes
// Author: COA Project
// Date: March 2026
//==============================================================================

`include "lsu_pkg.sv"

module data_memory
    import lsu_pkg::*;
#(
    parameter DEPTH       = MEM_DEPTH,
    parameter LATENCY     = 1,           // Memory access latency in cycles
    parameter INIT_FILE   = ""           // Optional initialization file
)(
    input  logic                    clk,
    input  logic                    rst_n,
    
    // Memory Interface
    input  logic                    req_valid_i,
    input  logic                    req_we_i,
    input  logic [ADDR_WIDTH-1:0]   req_addr_i,
    input  logic [DATA_WIDTH-1:0]   req_wdata_i,
    input  logic [3:0]              req_be_i,
    output logic                    req_ready_o,
    
    output logic                    resp_valid_o,
    output logic [DATA_WIDTH-1:0]   resp_rdata_o,
    output logic                    resp_error_o
);

    //==========================================================================
    // Memory Array
    //==========================================================================
    logic [7:0] mem [DEPTH];
    
    // Word-aligned address
    logic [$clog2(DEPTH)-1:0] word_addr;
    assign word_addr = req_addr_i[$clog2(DEPTH)-1+2:2] << 2;

    //==========================================================================
    // Latency Pipeline
    //==========================================================================
    logic [LATENCY:0] valid_pipe;
    logic [DATA_WIDTH-1:0] data_pipe [LATENCY+1];
    logic we_pipe [LATENCY+1];
    
    // Request ready when pipeline not full
    assign req_ready_o = 1'b1;  // Single-port, always ready

    //==========================================================================
    // Memory Initialization
    //==========================================================================
    initial begin
        // Initialize memory to zero
        for (int i = 0; i < DEPTH; i++) begin
            mem[i] = 8'h00;
        end
        
        // Load initialization file if provided
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end

    //==========================================================================
    // Memory Read/Write Logic
    //==========================================================================
    logic [DATA_WIDTH-1:0] read_data;
    
    // Combinational read
    always_comb begin
        read_data = {mem[word_addr+3], mem[word_addr+2], 
                     mem[word_addr+1], mem[word_addr]};
    end
    
    // Sequential write with byte enables
    always_ff @(posedge clk) begin
        if (req_valid_i && req_we_i) begin
            if (req_be_i[0]) mem[word_addr]   <= req_wdata_i[7:0];
            if (req_be_i[1]) mem[word_addr+1] <= req_wdata_i[15:8];
            if (req_be_i[2]) mem[word_addr+2] <= req_wdata_i[23:16];
            if (req_be_i[3]) mem[word_addr+3] <= req_wdata_i[31:24];
        end
    end

    //==========================================================================
    // Response Pipeline (Configurable Latency)
    //==========================================================================
    generate
        if (LATENCY == 0) begin : gen_zero_latency
            assign resp_valid_o = req_valid_i && !req_we_i;
            assign resp_rdata_o = read_data;
            assign resp_error_o = 1'b0;
        end else begin : gen_latency_pipe
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    valid_pipe <= '0;
                    for (int i = 0; i <= LATENCY; i++) begin
                        data_pipe[i] <= '0;
                    end
                end else begin
                    // First stage
                    valid_pipe[0] <= req_valid_i && !req_we_i;
                    data_pipe[0]  <= read_data;
                    
                    // Pipeline stages
                    for (int i = 1; i <= LATENCY; i++) begin
                        valid_pipe[i] <= valid_pipe[i-1];
                        data_pipe[i]  <= data_pipe[i-1];
                    end
                end
            end
            
            assign resp_valid_o = valid_pipe[LATENCY];
            assign resp_rdata_o = data_pipe[LATENCY];
            assign resp_error_o = 1'b0;
        end
    endgenerate

    //==========================================================================
    // Debug: Memory Dump Task
    //==========================================================================
    task automatic dump_memory(
        input int start_addr,
        input int num_words
    );
        $display("=== Memory Dump (Start: 0x%08h, Words: %0d) ===", start_addr, num_words);
        for (int i = 0; i < num_words; i++) begin
            int addr = start_addr + (i * 4);
            $display("  [0x%08h]: 0x%02h%02h%02h%02h", 
                addr, mem[addr+3], mem[addr+2], mem[addr+1], mem[addr]);
        end
        $display("===============================================");
    endtask

endmodule
