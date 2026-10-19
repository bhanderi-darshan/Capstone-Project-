module ahb_i2c_controller (
    // AHB-Lite interface
    input  wire        HCLK,
    input  wire        HRESETn,
    input  wire [31:0] HADDR,
    input  wire [31:0] HWDATA,
    input  wire        HWRITE,
    input  wire        HSEL,
    input  wire [1:0]  HTRANS,
    input  wire        HREADY,

    output reg  [31:0] HRDATA,
    output wire        HREADYOUT,
    output wire        HRESP,

    // I2C interface
    output wire        scl,
    inout  wire        sda
);

    // =========================================
    // Register Bank
    // =========================================

    reg [31:0] CONTROL;
    reg [31:0] STATUS;
    reg [31:0] CLOCK_DIV;
    reg [31:0] TX_DATA;
    reg [31:0] RX_DATA;
    reg [31:0] COMMAND;
    reg [31:0] TIMEOUT;
    reg [31:0] IRQ;

    // =========================================
    // AHB Transfer Detection
    // =========================================

    wire ahb_valid;
    wire ahb_write;
    wire ahb_read;

    assign ahb_valid = HSEL && HREADY && HTRANS[1];
    assign ahb_write = ahb_valid && HWRITE;
    assign ahb_read  = ahb_valid && !HWRITE;

    // Single-cycle response
    assign HREADYOUT = 1'b1;
    assign HRESP     = 1'b0;

    // =========================================
    // Register Write
    // =========================================

    always @(posedge HCLK or negedge HRESETn) begin

        if (!HRESETn) begin

            CONTROL  <= 32'b0;
            STATUS   <= 32'b0;
            CLOCK_DIV <= 32'd100;
            TX_DATA  <= 32'b0;
            RX_DATA  <= 32'b0;
            COMMAND  <= 32'b0;
            TIMEOUT  <= 32'd1000;
            IRQ      <= 32'b0;

        end
        else begin

            if (ahb_write) begin

                case (HADDR[5:2])

                    4'h0: CONTROL   <= HWDATA;
                    4'h1: STATUS    <= HWDATA;
                    4'h2: CLOCK_DIV <= HWDATA;
                    4'h3: TX_DATA   <= HWDATA;
                    4'h4: RX_DATA   <= HWDATA;
                    4'h5: COMMAND   <= HWDATA;
                    4'h6: TIMEOUT   <= HWDATA;
                    4'h7: IRQ       <= HWDATA;

                    default: begin
                    end

                endcase

            end

        end
    end

    // =========================================
    // Register Read
    // =========================================

    always @(*) begin

        HRDATA = 32'b0;

        if (ahb_read) begin

            case (HADDR[5:2])

                4'h0: HRDATA = CONTROL;
                4'h1: HRDATA = STATUS;
                4'h2: HRDATA = CLOCK_DIV;
                4'h3: HRDATA = TX_DATA;
                4'h4: HRDATA = RX_DATA;
                4'h5: HRDATA = COMMAND;
                4'h6: HRDATA = TIMEOUT;
                4'h7: HRDATA = IRQ;

                default: HRDATA = 32'b0;

            endcase

        end
    end

    // =========================================
    // Temporary I2C Outputs
    // =========================================

    assign scl = 1'b1;
    assign sda = 1'bz;

endmodule