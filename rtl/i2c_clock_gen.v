module i2c_clock_gen (
    input  wire       clk,
    input  wire       reset,
    input  wire [15:0] clock_div,

    output reg        scl
);

    reg [15:0] counter;

    always @(posedge clk or posedge reset) begin

        if (reset) begin
            counter <= 16'd0;
            scl     <= 1'b1;
        end

        else begin

            if (counter >= clock_div) begin
                counter <= 16'd0;
                scl     <= ~scl;
            end

            else begin
                counter <= counter + 16'd1;
            end

        end

    end

endmodule