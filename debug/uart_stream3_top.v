// uart_stream3_top.v - A..Z stream with TX-line activity indicators.
// LED16: heartbeat (~1.6 Hz).
// LED15 lit = the TX line was LOW  at some point in the last ~0.15 s
// LED14 lit = the TX line was HIGH at some point in the last ~0.15 s
// Both lit = line is toggling. One lit = stuck at that level.
module uart_stream3_top (
    input  wire sys_clk,
    output wire uart_tx_pin,
    output wire led_alive,
    output wire led_saw_low,
    output wire led_saw_high
);
    // power-on reset: hold rst_n low for the first 16 clocks so every state
    // machine starts in a known state (FPGA flops power up as all-zero)
    reg [3:0] por = 4'd0;
    always @(posedge sys_clk) if (por != 4'hF) por <= por + 4'd1;
    wire rst_n = (por == 4'hF);
    reg [23:0] tmr = 24'd0;
    reg [7:0]  ch = 8'h41, data = 8'h41;
    reg        send = 1'b0;
    wire       busy;

    uart_tx #(.CLK_FREQ(27_000_000), .BAUD(115_200)) u (
        .clk(sys_clk), .rst_n(rst_n), .data(data), .send(send),
        .tx(uart_tx_pin), .busy(busy));

    always @(posedge sys_clk) begin
        tmr  <= tmr + 24'd1;
        send <= 1'b0;
        if (!busy && !send) begin
            data <= ch;
            send <= 1'b1;
            ch   <= (ch == 8'h5A) ? 8'h41 : ch + 8'd1;
        end
    end

    reg [21:0] lo_cnt = 22'd0, hi_cnt = 22'd0;
    always @(posedge sys_clk) begin
        if (!uart_tx_pin)      lo_cnt <= 22'h3FFFFF;
        else if (lo_cnt != 0)  lo_cnt <= lo_cnt - 22'd1;
        if (uart_tx_pin)       hi_cnt <= 22'h3FFFFF;
        else if (hi_cnt != 0)  hi_cnt <= hi_cnt - 22'd1;
    end

    assign led_alive     = tmr[23];
    assign led_saw_low   = ~(lo_cnt != 0);   // active-low LED: 0 = lit
    assign led_saw_high  = ~(hi_cnt != 0);
endmodule