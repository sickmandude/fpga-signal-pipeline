// uart_test_top.v
// Minimal UART bring-up: sends the letters A..Z repeatedly, one every 100 ms,
// using the already-simulated uart_tx. No ADC, no filter. If this shows
// nothing on the Mac, the problem is the pin or the serial port, not our logic.

module uart_test_top (
    input  wire sys_clk,     // 27 MHz
    input  wire sys_rst_n,
    output wire uart_tx_pin,
    output wire led_alive    // toggles every send, so you can see it running
);

    reg [21:0] tmr;          // 2,700,000 cycles = 100 ms at 27 MHz
    reg [7:0]  ch;
    reg [7:0]  data;
    reg        send;
    reg        alive;
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
            tmr   <= 22'd0;
            ch    <= 8'h41;      // 'A'
            data  <= 8'h41;
            send  <= 1'b0;
            alive <= 1'b0;
        end else begin
            send <= 1'b0;
            if (tmr == 22'd2_699_999) begin
                tmr   <= 22'd0;
                data  <= ch;
                send  <= 1'b1;
                alive <= ~alive;
                ch    <= (ch == 8'h5A) ? 8'h41 : ch + 8'd1;   // 'Z' wraps to 'A'
            end else begin
                tmr <= tmr + 22'd1;
            end
        end
    end

    assign led_alive = alive;

endmodule
