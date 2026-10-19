`timescale 1ns/1ps

module i2c_master_tb;

    reg clk;
    reg reset;
    reg start;
    reg rw;
    reg [6:0] slave_addr;
    reg [7:0] tx_data;
    reg repeated_start;

    wire [7:0] rx_data;
    wire busy;
    wire done;
    wire ack_error;
    wire scl;
    wire sda;

    reg [7:0] slave_read_data;

    assign sda =
        (dut.state == 4'd3) ? 1'b0 :
        (dut.state == 4'd6) ? slave_read_data[dut.bit_count] :
        1'bz;

    i2c_master dut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .rw(rw),
        .slave_addr(slave_addr),
        .tx_data(tx_data),
        .repeated_start(repeated_start),
        .rx_data(rx_data),
        .busy(busy),
        .done(done),
        .ack_error(ack_error),
        .scl(scl),
        .sda(sda)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 0;
        reset = 1;
        start = 0;
        rw = 0;
        slave_addr = 7'h50;
        tx_data = 8'hA5;
        repeated_start = 0;
        slave_read_data = 8'h3C;

        #20;
        reset = 0;

        #20;

        start = 1;
        #10;
        start = 0;

        wait (dut.state == 4'd5);

        rw = 1;
        repeated_start = 1;

        #10;
        repeated_start = 0;

        wait (done == 1'b1);

        #10;

        $display("--------------------------------");
        $display("REPEATED START TEST");
        $display("RX_DATA   = %h", rx_data);
        $display("DONE      = %b", done);
        $display("ACK_ERROR = %b", ack_error);
        $display("--------------------------------");

        $finish;
    end

endmodule;