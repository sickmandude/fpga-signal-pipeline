module adc_fir_top (
    input  wire        sys_clk,     // 27 MHz onboard Tang Nano 9K clock
    input  wire        sys_rst_n,

    // ---- MCP3008 physical pins ----
    output wire        adc_sclk,
    output wire        adc_cs_n,
    output wire        adc_mosi,
    input  wire        adc_miso,

    // ---- filtered output, for whatever comes next (UART, LEDs, threshold logic...) ----
    output wire signed [31:0] filtered_sample,
    output wire                filtered_valid
);

    // ---- 1. Sample-rate timer: fires a new ADC conversion every 100us (10kHz) ----
    wire sample_tick;
    sample_rate_timer #(.CLK_FREQ(27_000_000), .SAMPLE_RATE(10_000)) timer_inst (
        .clk   (sys_clk),
        .rst_n (sys_rst_n),
        .tick  (sample_tick)
    );

    // ---- 2. SPI master: talks to the MCP3008 ----
    wire [9:0] adc_raw;
    wire       adc_data_valid;
    wire       adc_busy;

    mcp3008_spi_master #(.SCLK_DIV(14)) spi_inst (
        .clk        (sys_clk),
        .rst_n      (sys_rst_n),
        .start      (sample_tick),   // NOTE: only safe because one conversion (~18us)
                                      // finishes well within one 100us sample period -
                                      // see explanation below
        .channel    (3'd0),          // reading channel 0 for now
        .sclk       (adc_sclk),
        .cs_n       (adc_cs_n),
        .mosi       (adc_mosi),
        .miso       (adc_miso),
        .adc_data   (adc_raw),
        .data_valid (adc_data_valid),
        .busy       (adc_busy)
    );

    // ---- 3. Scale: unsigned 10-bit ADC code -> signed 16-bit, centered at 0 ----
    // The MCP3008 only ever outputs 0-1023 (unsigned) representing 0V to +Vref.
    // To represent a bipolar signal (positive AND negative), the analog front-end
    // must bias the input to Vref/2 so that "no signal" reads ~512 (midscale).
    // We then subtract that midpoint and left-shift into the full signed 16-bit
    // range the FIR filter expects (same Q1.15-style scaling used in reference.py).
    //
    // NOTE: sample_in only needs to be combinational here (not registered) -
    // the FIR filter itself only ever looks at it for one cycle, right when
    // 'start' (= adc_data_valid) fires, so there's no need to hold/latch it.
    wire signed [15:0] sample_in;
    assign sample_in = ($signed({1'b0, adc_raw}) - 16'sd512) <<< 6;

    // ---- 4. FIR filter: TRIGGERED version - only runs a pass when a genuinely
    //      new ADC sample arrives (adc_data_valid), instead of free-running.
    //      This is the fix for the sample-rate mismatch bug: the filter's
    //      31-tap delay line must only shift once per real 10kHz sample, not
    //      once every 31 system-clock cycles regardless of whether new data
    //      has actually arrived. ----
    fir_filter_31tap_tm_triggered fir_inst (
        .clk        (sys_clk),
        .rst_n      (sys_rst_n),
        .start      (adc_data_valid),
        .sample_in  (sample_in),
        .sample_out (filtered_sample),
        .out_valid  (filtered_valid),
        .busy       ()  // unused here - the ADC period (2700 cycles) is far
                         // longer than a filter pass (~32 cycles), so there's
                         // no risk of the filter still being busy when the
                         // next adc_data_valid arrives
    );

endmodule
