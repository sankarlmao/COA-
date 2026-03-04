//==============================================================================
// File: lsu_tb.sv
// Description: Comprehensive Testbench for RISC-V Load Store Unit
//              Tests all load/store instructions, alignment, forwarding
// Author: COA Project
// Date: March 2026
//==============================================================================

`timescale 1ns/1ps

`include "lsu_pkg.sv"

module lsu_tb;
    import lsu_pkg::*;

    //==========================================================================
    // Parameters
    //==========================================================================
    parameter CLK_PERIOD = 10;  // 100MHz clock
    parameter TEST_TIMEOUT = 10000;

    //==========================================================================
    // DUT Signals
    //==========================================================================
    logic                    clk;
    logic                    rst_n;
    
    // CPU Interface
    logic                    cpu_req_valid;
    logic                    cpu_req_we;
    logic [ADDR_WIDTH-1:0]   cpu_req_base_addr;
    logic [11:0]             cpu_req_offset;
    logic [DATA_WIDTH-1:0]   cpu_req_wdata;
    logic [2:0]              cpu_req_funct3;
    logic [4:0]              cpu_req_rd;
    logic                    cpu_req_ready;
    
    logic                    cpu_resp_valid;
    logic [DATA_WIDTH-1:0]   cpu_resp_rdata;
    logic [4:0]              cpu_resp_rd;
    logic                    cpu_resp_error;
    logic [3:0]              cpu_resp_exc_code;
    logic                    cpu_resp_ready;
    
    logic                    commit;
    logic                    flush;
    
    // Memory Interface
    logic                    mem_req_valid;
    logic                    mem_req_we;
    logic [ADDR_WIDTH-1:0]   mem_req_addr;
    logic [DATA_WIDTH-1:0]   mem_req_wdata;
    logic [3:0]              mem_req_be;
    logic                    mem_req_ready;
    
    logic                    mem_resp_valid;
    logic [DATA_WIDTH-1:0]   mem_resp_rdata;
    logic                    mem_resp_error;
    
    // Status
    logic                    lsu_busy;
    logic                    lb_full;
    logic                    sb_full;

    //==========================================================================
    // Test Statistics
    //==========================================================================
    int test_count = 0;
    int pass_count = 0;
    int fail_count = 0;

    //==========================================================================
    // Clock Generation
    //==========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //==========================================================================
    // DUT Instantiation
    //==========================================================================
    lsu_top u_dut (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .cpu_req_valid_i        (cpu_req_valid),
        .cpu_req_we_i           (cpu_req_we),
        .cpu_req_base_addr_i    (cpu_req_base_addr),
        .cpu_req_offset_i       (cpu_req_offset),
        .cpu_req_wdata_i        (cpu_req_wdata),
        .cpu_req_funct3_i       (cpu_req_funct3),
        .cpu_req_rd_i           (cpu_req_rd),
        .cpu_req_ready_o        (cpu_req_ready),
        .cpu_resp_valid_o       (cpu_resp_valid),
        .cpu_resp_rdata_o       (cpu_resp_rdata),
        .cpu_resp_rd_o          (cpu_resp_rd),
        .cpu_resp_error_o       (cpu_resp_error),
        .cpu_resp_exc_code_o    (cpu_resp_exc_code),
        .cpu_resp_ready_i       (cpu_resp_ready),
        .commit_i               (commit),
        .flush_i                (flush),
        .mem_req_valid_o        (mem_req_valid),
        .mem_req_we_o           (mem_req_we),
        .mem_req_addr_o         (mem_req_addr),
        .mem_req_wdata_o        (mem_req_wdata),
        .mem_req_be_o           (mem_req_be),
        .mem_req_ready_i        (mem_req_ready),
        .mem_resp_valid_i       (mem_resp_valid),
        .mem_resp_rdata_i       (mem_resp_rdata),
        .mem_resp_error_i       (mem_resp_error),
        .lsu_busy_o             (lsu_busy),
        .load_buffer_full_o     (lb_full),
        .store_buffer_full_o    (sb_full)
    );

    //==========================================================================
    // Data Memory Instantiation
    //==========================================================================
    data_memory #(
        .DEPTH      (4096),
        .LATENCY    (1)
    ) u_data_mem (
        .clk            (clk),
        .rst_n          (rst_n),
        .req_valid_i    (mem_req_valid),
        .req_we_i       (mem_req_we),
        .req_addr_i     (mem_req_addr),
        .req_wdata_i    (mem_req_wdata),
        .req_be_i       (mem_req_be),
        .req_ready_o    (mem_req_ready),
        .resp_valid_o   (mem_resp_valid),
        .resp_rdata_o   (mem_resp_rdata),
        .resp_error_o   (mem_resp_error)
    );

    //==========================================================================
    // Test Tasks
    //==========================================================================
    
    // Reset task
    task automatic reset_dut();
        $display("\n[%0t] Applying reset...", $time);
        rst_n = 0;
        cpu_req_valid = 0;
        cpu_req_we = 0;
        cpu_req_base_addr = 0;
        cpu_req_offset = 0;
        cpu_req_wdata = 0;
        cpu_req_funct3 = 0;
        cpu_req_rd = 0;
        cpu_resp_ready = 1;
        commit = 0;
        flush = 0;
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);
        $display("[%0t] Reset complete\n", $time);
    endtask

    // Store word task
    task automatic store_word(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [DATA_WIDTH-1:0] data
    );
        $display("[%0t] STORE WORD: addr=0x%08h, data=0x%08h", $time, addr, data);
        @(posedge clk);
        cpu_req_valid     <= 1;
        cpu_req_we        <= 1;
        cpu_req_base_addr <= addr;
        cpu_req_offset    <= 0;
        cpu_req_wdata     <= data;
        cpu_req_funct3    <= FUNCT3_SW;
        
        // Wait for request accepted
        wait(cpu_req_ready);
        @(posedge clk);
        cpu_req_valid <= 0;
        
        // Commit the store
        repeat(2) @(posedge clk);
        commit <= 1;
        @(posedge clk);
        commit <= 0;
        
        // Wait for completion
        repeat(5) @(posedge clk);
    endtask

    // Store halfword task
    task automatic store_halfword(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [15:0] data
    );
        $display("[%0t] STORE HALF: addr=0x%08h, data=0x%04h", $time, addr, data);
        @(posedge clk);
        cpu_req_valid     <= 1;
        cpu_req_we        <= 1;
        cpu_req_base_addr <= addr;
        cpu_req_offset    <= 0;
        cpu_req_wdata     <= {16'b0, data};
        cpu_req_funct3    <= FUNCT3_SH;
        
        wait(cpu_req_ready);
        @(posedge clk);
        cpu_req_valid <= 0;
        
        repeat(2) @(posedge clk);
        commit <= 1;
        @(posedge clk);
        commit <= 0;
        
        repeat(5) @(posedge clk);
    endtask

    // Store byte task
    task automatic store_byte(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [7:0] data
    );
        $display("[%0t] STORE BYTE: addr=0x%08h, data=0x%02h", $time, addr, data);
        @(posedge clk);
        cpu_req_valid     <= 1;
        cpu_req_we        <= 1;
        cpu_req_base_addr <= addr;
        cpu_req_offset    <= 0;
        cpu_req_wdata     <= {24'b0, data};
        cpu_req_funct3    <= FUNCT3_SB;
        
        wait(cpu_req_ready);
        @(posedge clk);
        cpu_req_valid <= 0;
        
        repeat(2) @(posedge clk);
        commit <= 1;
        @(posedge clk);
        commit <= 0;
        
        repeat(5) @(posedge clk);
    endtask

    // Load word task
    task automatic load_word(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [4:0] rd,
        output logic [DATA_WIDTH-1:0] data
    );
        $display("[%0t] LOAD WORD: addr=0x%08h, rd=x%0d", $time, addr, rd);
        @(posedge clk);
        cpu_req_valid     <= 1;
        cpu_req_we        <= 0;
        cpu_req_base_addr <= addr;
        cpu_req_offset    <= 0;
        cpu_req_funct3    <= FUNCT3_LW;
        cpu_req_rd        <= rd;
        
        wait(cpu_req_ready);
        @(posedge clk);
        cpu_req_valid <= 0;
        
        // Wait for response
        wait(cpu_resp_valid);
        data = cpu_resp_rdata;
        $display("[%0t] LOAD COMPLETE: data=0x%08h, rd=x%0d", $time, data, cpu_resp_rd);
        @(posedge clk);
    endtask

    // Load halfword (signed) task
    task automatic load_halfword(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [4:0] rd,
        output logic [DATA_WIDTH-1:0] data
    );
        $display("[%0t] LOAD HALF: addr=0x%08h, rd=x%0d", $time, addr, rd);
        @(posedge clk);
        cpu_req_valid     <= 1;
        cpu_req_we        <= 0;
        cpu_req_base_addr <= addr;
        cpu_req_offset    <= 0;
        cpu_req_funct3    <= FUNCT3_LH;
        cpu_req_rd        <= rd;
        
        wait(cpu_req_ready);
        @(posedge clk);
        cpu_req_valid <= 0;
        
        wait(cpu_resp_valid);
        data = cpu_resp_rdata;
        $display("[%0t] LOAD COMPLETE: data=0x%08h (sign-extended)", $time, data);
        @(posedge clk);
    endtask

    // Load byte (signed) task
    task automatic load_byte(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [4:0] rd,
        output logic [DATA_WIDTH-1:0] data
    );
        $display("[%0t] LOAD BYTE: addr=0x%08h, rd=x%0d", $time, addr, rd);
        @(posedge clk);
        cpu_req_valid     <= 1;
        cpu_req_we        <= 0;
        cpu_req_base_addr <= addr;
        cpu_req_offset    <= 0;
        cpu_req_funct3    <= FUNCT3_LB;
        cpu_req_rd        <= rd;
        
        wait(cpu_req_ready);
        @(posedge clk);
        cpu_req_valid <= 0;
        
        wait(cpu_resp_valid);
        data = cpu_resp_rdata;
        $display("[%0t] LOAD COMPLETE: data=0x%08h (sign-extended)", $time, data);
        @(posedge clk);
    endtask

    // Check result task
    task automatic check_result(
        input string test_name,
        input logic [DATA_WIDTH-1:0] actual,
        input logic [DATA_WIDTH-1:0] expected
    );
        test_count++;
        if (actual == expected) begin
            pass_count++;
            $display("[PASS] %s: Expected=0x%08h, Got=0x%08h", test_name, expected, actual);
        end else begin
            fail_count++;
            $display("[FAIL] %s: Expected=0x%08h, Got=0x%08h", test_name, expected, actual);
        end
    endtask

    //==========================================================================
    // Test Sequences
    //==========================================================================
    
    // Test 1: Basic Word Store and Load
    task automatic test_basic_word_access();
        logic [DATA_WIDTH-1:0] read_data;
        $display("\n========== TEST 1: Basic Word Store/Load ==========");
        
        store_word(32'h0000_0100, 32'hDEAD_BEEF);
        load_word(32'h0000_0100, 5'd1, read_data);
        check_result("Word Store/Load", read_data, 32'hDEAD_BEEF);
        
        store_word(32'h0000_0104, 32'hCAFE_BABE);
        load_word(32'h0000_0104, 5'd2, read_data);
        check_result("Word Store/Load 2", read_data, 32'hCAFE_BABE);
    endtask

    // Test 2: Byte Access
    task automatic test_byte_access();
        logic [DATA_WIDTH-1:0] read_data;
        $display("\n========== TEST 2: Byte Store/Load ==========");
        
        // Store individual bytes
        store_byte(32'h0000_0200, 8'hAA);
        store_byte(32'h0000_0201, 8'hBB);
        store_byte(32'h0000_0202, 8'hCC);
        store_byte(32'h0000_0203, 8'hDD);
        
        // Load as word
        load_word(32'h0000_0200, 5'd3, read_data);
        check_result("Byte->Word", read_data, 32'hDDCC_BBAA);
        
        // Load individual bytes
        load_byte(32'h0000_0200, 5'd4, read_data);
        check_result("Load Byte 0", read_data, 32'hFFFF_FFAA);  // Sign-extended (AA is negative)
        
        // Store and load positive byte
        store_byte(32'h0000_0210, 8'h7F);
        load_byte(32'h0000_0210, 5'd5, read_data);
        check_result("Load Byte Positive", read_data, 32'h0000_007F);
    endtask

    // Test 3: Halfword Access
    task automatic test_halfword_access();
        logic [DATA_WIDTH-1:0] read_data;
        $display("\n========== TEST 3: Halfword Store/Load ==========");
        
        store_halfword(32'h0000_0300, 16'h1234);
        store_halfword(32'h0000_0302, 16'h5678);
        
        // Load as word
        load_word(32'h0000_0300, 5'd6, read_data);
        check_result("Half->Word", read_data, 32'h5678_1234);
        
        // Load halfword (sign-extended)
        load_halfword(32'h0000_0300, 5'd7, read_data);
        check_result("Load Halfword", read_data, 32'h0000_1234);
        
        // Test negative halfword
        store_halfword(32'h0000_0310, 16'hFFFF);
        load_halfword(32'h0000_0310, 5'd8, read_data);
        check_result("Load Halfword Negative", read_data, 32'hFFFF_FFFF);
    endtask

    // Test 4: Address with Offset
    task automatic test_address_offset();
        logic [DATA_WIDTH-1:0] read_data;
        $display("\n========== TEST 4: Address with Offset ==========");
        
        // Store using base + offset
        store_word(32'h0000_0400, 32'h1111_2222);
        
        // Load using different base + offset combinations
        cpu_req_valid     <= 1;
        cpu_req_we        <= 0;
        cpu_req_base_addr <= 32'h0000_03F0;  // Base
        cpu_req_offset    <= 12'h010;         // Offset = +16
        cpu_req_funct3    <= FUNCT3_LW;
        cpu_req_rd        <= 5'd9;
        
        wait(cpu_req_ready);
        @(posedge clk);
        cpu_req_valid <= 0;
        
        wait(cpu_resp_valid);
        read_data = cpu_resp_rdata;
        @(posedge clk);
        
        check_result("Base+Offset", read_data, 32'h1111_2222);
    endtask

    // Test 5: Multiple Operations
    task automatic test_multiple_operations();
        logic [DATA_WIDTH-1:0] read_data;
        $display("\n========== TEST 5: Multiple Operations ==========");
        
        // Sequence of stores
        store_word(32'h0000_0500, 32'h0000_0001);
        store_word(32'h0000_0504, 32'h0000_0002);
        store_word(32'h0000_0508, 32'h0000_0003);
        store_word(32'h0000_050C, 32'h0000_0004);
        
        // Sequence of loads
        load_word(32'h0000_0500, 5'd10, read_data);
        check_result("Multi Op 1", read_data, 32'h0000_0001);
        
        load_word(32'h0000_0504, 5'd11, read_data);
        check_result("Multi Op 2", read_data, 32'h0000_0002);
        
        load_word(32'h0000_0508, 5'd12, read_data);
        check_result("Multi Op 3", read_data, 32'h0000_0003);
        
        load_word(32'h0000_050C, 5'd13, read_data);
        check_result("Multi Op 4", read_data, 32'h0000_0004);
    endtask

    //==========================================================================
    // Main Test Sequence
    //==========================================================================
    initial begin
        $display("\n");
        $display("╔═══════════════════════════════════════════════════════════╗");
        $display("║       RISC-V Load Store Unit - Testbench                  ║");
        $display("║                   COA Project                             ║");
        $display("╚═══════════════════════════════════════════════════════════╝");
        $display("\n");

        // Initialize
        reset_dut();
        
        // Run tests
        test_basic_word_access();
        test_byte_access();
        test_halfword_access();
        test_address_offset();
        test_multiple_operations();
        
        // Results summary
        $display("\n");
        $display("╔═══════════════════════════════════════════════════════════╗");
        $display("║                    TEST SUMMARY                           ║");
        $display("╠═══════════════════════════════════════════════════════════╣");
        $display("║  Total Tests:  %3d                                        ║", test_count);
        $display("║  Passed:       %3d                                        ║", pass_count);
        $display("║  Failed:       %3d                                        ║", fail_count);
        $display("╚═══════════════════════════════════════════════════════════╝");
        
        if (fail_count == 0) begin
            $display("\n*** ALL TESTS PASSED ***\n");
        end else begin
            $display("\n*** SOME TESTS FAILED ***\n");
        end
        
        #100;
        $finish;
    end

    //==========================================================================
    // Timeout Watchdog
    //==========================================================================
    initial begin
        #(TEST_TIMEOUT * CLK_PERIOD);
        $display("\n[ERROR] Test timeout! Simulation terminated.\n");
        $finish;
    end

    //==========================================================================
    // Waveform Dump
    //==========================================================================
    initial begin
        $dumpfile("lsu_tb.vcd");
        $dumpvars(0, lsu_tb);
    end

endmodule
