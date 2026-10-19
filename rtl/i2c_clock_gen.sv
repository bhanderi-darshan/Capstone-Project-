module i2c_clock_gen (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        enable,
    input  logic [15:0] clk_div,
    output logic        scl_tick
);

    logic [15:0] counter;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            counter  <= 16'd0;
            scl_tick <= 1'b0;
        end
        else begin
            scl_tick <= 1'b0;

            if (!enable) begin
                counter <= 16'd0;
            end
            else if (clk_div == 16'd0) begin
                counter  <= 16'd0;
                scl_tick <= 1'b1;
            end
            else if (counter >= clk_div - 1'b1) begin
                counter  <= 16'd0;
                scl_tick <= 1'b1;
            end
            else begin
                counter <= counter + 1'b1;
            end
        end
    end

endmodule