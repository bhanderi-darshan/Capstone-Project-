`timescale 1ns/1ps

module i2c_clock_gen_tb;

    logic        clk;
    logic        reset_n;
    logic        enable;
    logic [15:0] clk_div;
    logic        scl_tick;

    i2c_clock_gen dut (
        .clk      (clk),
        .reset_n  (reset_n),
        .enable   (enable),
        .clk_div  (clk_div),
        .scl_tick (scl_tick)
    );

    // 10 ns clock period = 100 MHz
    always #5 clk = ~clk;

    initial begin

        $dumpfile("sim/i2c_clock_gen.vcd");
        $dumpvars(0, i2c_clock_gen_tb);

        clk     = 1'b0;
        reset_n = 1'b0;
        enable  = 1'b0;
        clk_div = 16'd4;

        // Reset
        #20;

        // Enable generator
        reset_n = 1'b1;
        enable  = 1'b1;

        // Run
        #200;

        // Disable
        enable = 1'b0;

        #20;

        $finish;
    end

endmodule