module i2c_timeout (
    input  wire       clk,
    input  wire       reset,

    // 1 = timeout monitoring enabled
    input  wire       enable,

    // 1 = master has released SCL and expects it HIGH
    input  wire       scl_release,

    // Actual SCL bus level
    input  wire       scl_in,

    // Programmable timeout limit
    input  wire [15:0] timeout_limit,

    output reg        stretching,
    output reg        timeout
);

    reg [15:0] counter;

    always @(posedge clk or posedge reset) begin

        if (reset) begin
            counter   <= 16'd0;
            stretching <= 1'b0;
            timeout   <= 1'b0;
        end

        else begin

            stretching <= 1'b0;

            if (!enable) begin
                counter <= 16'd0;
                timeout <= 1'b0;
            end

            else if (scl_release && !scl_in) begin

                // Slave is holding SCL LOW
                stretching <= 1'b1;

                if (counter < timeout_limit) begin
                    counter <= counter + 16'd1;
                end
                else begin
                    timeout <= 1'b1;
                end
            end

            else begin
                // SCL is not being stretched
                counter <= 16'd0;
                timeout <= 1'b0;
            end
        end
    end

endmodule