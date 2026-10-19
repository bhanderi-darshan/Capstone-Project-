`timescale 1ns/1ps

module ahb_i2c_controller_tb;

    reg clk;
    reg reset;

    wire scl;
    wire sda;

    // DUT
    ahb_i2c_controller uut (
        .clk   (clk),
        .reset (reset),
        .scl   (scl),
        .sda   (sda)
    );

    // Clock generation: 10 ns period
    always #5 clk = ~clk;

    initial begin
        clk   = 1'b0;
        reset = 1'b1;

        // Hold reset
        #20;

        reset = 1'b0;

        // Run simulation
        #200;

        $stop;
    end

endmodule	