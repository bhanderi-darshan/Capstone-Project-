`timescale 1ns/1ps

module test_counter_tb;

    logic       clk;
    logic       reset_n;
    logic       enable;
    logic [3:0] count;

    test_counter dut (
        .clk     (clk),
        .reset_n (reset_n),
        .enable  (enable),
        .count   (count)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("sim/test_counter.vcd");
        $dumpvars(0, test_counter_tb);

        clk     = 1'b0;
        reset_n = 1'b0;
        enable  = 1'b0;

        #20;

        reset_n = 1'b1;
        enable  = 1'b1;

        #100;

        enable = 1'b0;

        #20;

        $finish;
    end

endmodule