// uart_stream_top.v
// UART bring-up v2: sends the letters A..Z back-to-back, continuously
// (about 11,500 bytes/s at 115200 baud), so the TX line is busy ~100% of the
// time. That makes the bridge's activity LED visibly active, and a Mac-side
// read returns data within milliseconds.
//
// led_alive blinks at ~1.6 Hz from a free-running counter, just to show the
// FPGA is running.

module uart_stream_top (
    input  wire sys_clk,     // 27 MHz
    input  wire sys_rst_n,
    output wire uart_tx_pin,
    output wire led_alive
);

    reg [23:0] tmr;          // free-running; bit 23 toggles every ~0.31 s
    reg [7:0]  ch;
    reg [7:0]  data;
    reg        send;
    wire       busy;

    uart_tx #(.CLK_FREQ(27_000_000), .BAUD(115_200)) u (
        .clk   (sys_clk),
        .rst_n (sys_rst_n),
        .data  (data),
        .send  (send),
        .tx    (uart_tx_pin),
        .busy  (busy)
    );

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            tmr  <= 24'd0;
            ch   <= 8'h41;   // 'A'
            data <= 8'h41;
            send <= 1'b0;
        end else begin
            tmr  <= tmr + 24'd1;
            send <= 1'b0;
            // whenever the transmitter is free (and we are not already
            // mid-pulse), hand it the next letter
            if (!busy && !send) begin
                data <= ch;
                send <= 1'b1;
                ch   <= (ch == 8'h5A) ? 8'h41 : ch + 8'd1;   // 'Z' wraps to 'A'
            end
        end
    end

    assign led_alive = tmr[23];

endmodule
