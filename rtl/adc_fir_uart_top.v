// adc_fir_uart_top.v
// Full chain on the Tang Nano 9K:
//   MCP3008 --SPI--> FIR filter --> frame serializer --UART--> Mac
// Keeps the two LEDs from the debug build as a quick health check.

module adc_fir_uart_top (
    input  wire sys_clk,      // 27 MHz onboard clock
    input  wire sys_rst_n,

    // MCP3008
    output wire adc_sclk,
    output wire adc_cs_n,
    output wire adc_mosi,
    input  wire adc_miso,

    // to the board's USB-serial bridge (BL702)
    output wire uart_tx,

    // health LEDs (active-low on this board)
    output wire led_valid,
    output wire led_sign
);

    // ---- power-on reset ----
    // FPGA flops power up as all-zero, which is not a valid state for the
    // state machines. Hold reset for the first 16 clocks, then follow the button.
    reg [3:0] por = 4'd0;
    always @(posedge sys_clk) if (por != 4'hF) por <= por + 4'd1;
    wire rst_n = sys_rst_n & (por == 4'hF);

    // ---- 1. 10 kHz sample timer ----
    wire sample_tick;
    sample_rate_timer #(.CLK_FREQ(27_000_000), .SAMPLE_RATE(10_000)) timer_inst (
        .clk   (sys_clk),
        .rst_n (rst_n),
        .tick  (sample_tick)
    );

    // ---- 2. SPI master -> raw 10-bit code ----
    wire [9:0] adc_raw;
    wire       adc_data_valid;

    mcp3008_spi_master #(.SCLK_DIV(14)) spi_inst (
        .clk        (sys_clk),
        .rst_n      (rst_n),
        .start      (sample_tick),
        .channel    (3'd0),
        .sclk       (adc_sclk),
        .cs_n       (adc_cs_n),
        .mosi       (adc_mosi),
        .miso       (adc_miso),
        .adc_data   (adc_raw),
        .data_valid (adc_data_valid),
        .busy       ()
    );

    // ---- 3. scale unsigned code to signed 16-bit centered on 0 ----
    wire signed [15:0] sample_in;
    assign sample_in = ($signed({1'b0, adc_raw}) - 16'sd512) <<< 6;

    // ---- 4. triggered FIR ----
    wire signed [31:0] filtered_sample;
    wire               filtered_valid;

    fir_filter_31tap_tm_triggered fir_inst (
        .clk        (sys_clk),
        .rst_n      (rst_n),
        .start      (adc_data_valid),
        .sample_in  (sample_in),
        .sample_out (filtered_sample),
        .out_valid  (filtered_valid),
        .busy       ()
    );

    // ---- 5. frame serializer + UART ----
    // adc_raw is held stable by the SPI master until the next conversion
    // (2700 cycles later), and filtered_valid fires ~33 cycles after
    // adc_data_valid, so adc_raw here is the same sample that was just filtered.
    sample_tx #(.CLK_FREQ(27_000_000), .BAUD(115_200), .DECIM(64)) tx_inst (
        .clk      (sys_clk),
        .rst_n    (rst_n),
        .valid    (filtered_valid),
        .filtered (filtered_sample),
        .adc_raw  (adc_raw),
        .tx       (uart_tx)
    );

    // ---- health LEDs (same behavior as adc_fir_top_debug) ----
    reg valid_latch;
    reg sign_latch;

    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_latch <= 1'b0;
            sign_latch  <= 1'b0;
        end else if (filtered_valid) begin
            valid_latch <= ~valid_latch;
            sign_latch  <= filtered_sample[31];
        end
    end

    assign led_valid = valid_latch;
    assign led_sign  = sign_latch;

endmodule