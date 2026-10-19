module test_counter (
    input  logic       clk,
    input  logic       reset_n,
    input  logic       enable,
    output logic [3:0] count
);

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            count <= 4'd0;
        else if (enable)
            count <= count + 4'd1;
    end

endmodule