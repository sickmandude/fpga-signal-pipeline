module mcp3008_spi_master #(
    parameter SCLK_DIV = 14   // SCLK freq = clk / (2*SCLK_DIV). At 27MHz, DIV=14 -> ~964kHz
                              // (safely under the 1.35MHz/2.7V-rated limit, comfortable margin)
)(
    input  wire        clk,       // 27 MHz system clock
    input  wire        rst_n,
    input  wire        start,     // pulse high for 1 cycle to begin one conversion
    input  wire [2:0]  channel,   // MCP3008 channel to read, 0-7

    output reg          sclk,
    output reg          cs_n,
    output reg          mosi,
    input  wire         miso,

    output reg  [9:0]   adc_data,   // last completed 10-bit result
    output reg           data_valid, // 1-cycle pulse when adc_data is fresh
    output reg           busy
);

    // ---- clock divider: turns the 27MHz system clock into SCLK edges ----
    // sclk_tick pulses for exactly one system-clock cycle each time SCLK
    // should toggle. Only runs while a conversion is in progress.
    reg [7:0] div_cnt;
    reg       sclk_tick;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_cnt   <= 8'd0;
            sclk_tick <= 1'b0;
        end else if (busy) begin
            if (div_cnt == SCLK_DIV - 1) begin
                div_cnt   <= 8'd0;
                sclk_tick <= 1'b1;
            end else begin
                div_cnt   <= div_cnt + 8'd1;
                sclk_tick <= 1'b0;
            end
        end else begin
            div_cnt   <= 8'd0;
            sclk_tick <= 1'b0;
        end
    end

    // ---- bit counter: which of the 17 SCLK rising edges we're on (0..16) ----
    // idx 0     : start bit  (DIN=1)
    // idx 1     : SGL/DIFF   (DIN=1, single-ended)
    // idx 2-4   : D2,D1,D0   (DIN=channel select)
    // idx 5     : sample/hold wait cycle (DIN=don't care)
    // idx 6     : null bit on DOUT (discarded)
    // idx 7-16  : B9..B0 on DOUT (10 data bits, captured)
    reg [4:0] bit_cnt;
    reg [4:0] mosi_shift;   // {start, sgl/diff, D2, D1, D0}
    reg [9:0] miso_shift;   // captured data bits, shifted in MSB-first

    localparam S_IDLE  = 2'd0;
    localparam S_SETUP = 2'd1;
    localparam S_LOW   = 2'd2;
    localparam S_HIGH  = 2'd3;

    reg [1:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            sclk       <= 1'b0;
            cs_n       <= 1'b1;
            mosi       <= 1'b0;
            busy       <= 1'b0;
            data_valid <= 1'b0;
            bit_cnt    <= 5'd0;
            mosi_shift <= 5'd0;
            miso_shift <= 10'd0;
            adc_data   <= 10'd0;
        end else begin
            data_valid <= 1'b0;  // default: only pulses high for 1 cycle

            case (state)
                // ---- wait for a start pulse ----
                S_IDLE: begin
                    sclk <= 1'b0;
                    cs_n <= 1'b1;
                    if (start) begin
                        cs_n       <= 1'b0;
                        mosi_shift <= {1'b1, 1'b1, channel}; // start, SGL/DIFF=1, D2 D1 D0
                        bit_cnt    <= 5'd0;
                        miso_shift <= 10'd0;
                        busy       <= 1'b1;
                        state      <= S_SETUP;
                    end
                end

                // ---- CS just went low; hold SCLK low one half-period before
                //      the first rising edge, with the start bit already on MOSI ----
                S_SETUP: begin
                    mosi <= mosi_shift[4]; // start bit, ready ahead of idx0's rising edge
                    if (sclk_tick) state <= S_LOW;
                end

                // ---- SCLK is low; sclk_tick means it's time for a rising edge ----
                S_LOW: begin
                    if (sclk_tick) begin
                        sclk <= 1'b1;

                        // capture MISO on this rising edge if we're in the data phase
                        if (bit_cnt >= 5'd7)
                            miso_shift <= {miso_shift[8:0], miso};

                        state <= S_HIGH;
                    end
                end

                // ---- SCLK is high; sclk_tick means it's time for a falling edge ----
                S_HIGH: begin
                    if (sclk_tick) begin
                        sclk <= 1'b0;

                        if (bit_cnt == 5'd16) begin
                            // miso_shift already holds the complete 10-bit result
                            // (the 10th and final capture just happened in S_LOW)
                            adc_data   <= miso_shift;
                            data_valid <= 1'b1;
                            busy       <= 1'b0;
                            cs_n       <= 1'b1;
                            state      <= S_IDLE;
                        end else begin
                            bit_cnt <= bit_cnt + 5'd1;
                            // present the next control bit, ready for the next rising edge
                            if (bit_cnt < 5'd4)
                                mosi <= mosi_shift[3 - bit_cnt]; // SGL/DIFF, D2, D1, D0 in turn
                            state <= S_LOW;
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
