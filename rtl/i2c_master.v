module i2c_master (
    input  wire       clk,
    input  wire       reset,

    input  wire       start,
    input  wire       rw,
    input  wire [6:0] slave_addr,
    input  wire [7:0] tx_data,

    input  wire       repeated_start,

    output reg  [7:0] rx_data,
    output reg        busy,
    output reg        done,
    output reg        ack_error,

    output reg        scl,
    inout  wire       sda
);

    localparam IDLE          = 4'd0;
    localparam START         = 4'd1;
    localparam ADDR          = 4'd2;
    localparam ADDR_ACK      = 4'd3;
    localparam WRITE_DATA    = 4'd4;
    localparam DATA_ACK      = 4'd5;
    localparam READ_DATA     = 4'd6;
    localparam MASTER_NACK   = 4'd7;
    localparam STOP          = 4'd8;
    localparam RESTART       = 4'd9;

    reg [3:0] state;
    reg [3:0] bit_count;

    reg [7:0] addr_byte;
    reg [7:0] data_byte;

    reg sda_out;
    reg sda_oe;

    wire sda_in;

    assign sda = sda_oe ? sda_out : 1'bz;
    assign sda_in = sda;

    always @(posedge clk or posedge reset) begin

        if (reset) begin
            state     <= IDLE;
            bit_count <= 4'd0;

            addr_byte <= 8'd0;
            data_byte <= 8'd0;
            rx_data   <= 8'd0;

            busy      <= 1'b0;
            done      <= 1'b0;
            ack_error <= 1'b0;

            scl       <= 1'b1;
            sda_out   <= 1'b1;
            sda_oe    <= 1'b1;
        end

        else begin

            done <= 1'b0;

            case (state)

                IDLE: begin
                    busy      <= 1'b0;
                    ack_error <= 1'b0;

                    scl     <= 1'b1;
                    sda_out <= 1'b1;
                    sda_oe  <= 1'b1;

                    if (start) begin
                        busy      <= 1'b1;
                        addr_byte <= {slave_addr, rw};
                        data_byte <= tx_data;
                        state     <= START;
                    end
                end

                // START
                START: begin
                    scl       <= 1'b1;
                    sda_out   <= 1'b0;
                    sda_oe    <= 1'b1;

                    bit_count <= 4'd7;
                    state     <= ADDR;
                end

                // Send address + R/W
                ADDR: begin
                    scl     <= 1'b0;
                    sda_oe  <= 1'b1;
                    sda_out <= addr_byte[bit_count];

                    scl <= 1'b1;

                    if (bit_count == 0) begin
                        state <= ADDR_ACK;
                    end
                    else begin
                        bit_count <= bit_count - 1'b1;
                    end
                end

                // Address ACK
                ADDR_ACK: begin
                    scl    <= 1'b0;
                    sda_oe <= 1'b0;

                    scl <= 1'b1;

                    if (sda_in == 1'b1)
                        ack_error <= 1'b1;

                    if (addr_byte[0]) begin
                        bit_count <= 4'd7;
                        rx_data   <= 8'd0;
                        state     <= READ_DATA;
                    end
                    else begin
                        bit_count <= 4'd7;
                        state     <= WRITE_DATA;
                    end
                end

                // WRITE DATA
                WRITE_DATA: begin
                    scl     <= 1'b0;
                    sda_oe  <= 1'b1;
                    sda_out <= data_byte[bit_count];

                    scl <= 1'b1;

                    if (bit_count == 0) begin
                        state <= DATA_ACK;
                    end
                    else begin
                        bit_count <= bit_count - 1'b1;
                    end
                end

                // DATA ACK
                DATA_ACK: begin
                    scl    <= 1'b0;
                    sda_oe <= 1'b0;

                    scl <= 1'b1;

                    if (sda_in == 1'b1)
                        ack_error <= 1'b1;

                    if (repeated_start) begin
                        state <= RESTART;
                    end
                    else begin
                        state <= STOP;
                    end
                end

                // REPEATED START
                RESTART: begin
                    scl     <= 1'b1;
                    sda_oe  <= 1'b1;

                    // SDA goes HIGH then LOW while SCL is HIGH
                    sda_out <= 1'b1;
                    sda_out <= 1'b0;

                    // Capture new address + R/W
                    addr_byte <= {slave_addr, rw};

                    bit_count <= 4'd7;
                    state     <= ADDR;
                end

                // READ DATA
                READ_DATA: begin
                    scl    <= 1'b0;
                    sda_oe <= 1'b0;

                    scl <= 1'b1;

                    rx_data[bit_count] <= sda_in;

                    if (bit_count == 0) begin
                        state <= MASTER_NACK;
                    end
                    else begin
                        bit_count <= bit_count - 1'b1;
                    end
                end

                // Master NACK
                MASTER_NACK: begin
                    scl     <= 1'b0;
                    sda_oe  <= 1'b1;
                    sda_out <= 1'b1;

                    scl   <= 1'b1;
                    state <= STOP;
                end

                // STOP
                STOP: begin
                    scl     <= 1'b1;
                    sda_oe  <= 1'b1;
                    sda_out <= 1'b1;

                    busy <= 1'b0;
                    done <= 1'b1;

                    state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                end

            endcase
        end
    end

endmodule