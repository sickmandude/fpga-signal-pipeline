// uart_gap_top.v - one letter (A..Z, cycling) every ~10 ms, line idle between bytes.
// Includes a power-on reset. LED pin16 heartbeat (~1.6 Hz).
module uart_gap_top (
    input  wire sys_clk,
    output wire uart_tx_pin,
    output wire led_alive
);
    reg [3:0] por = 4'd0;
    always @(posedge sys_clk) if (por != 4'hF) por <= por + 4'd1;
    wire rst_n = (por == 4'hF);

    reg [23:0] tmr = 24'd0;
    reg [18:0] gap = 19'd0;           // 2^18 = 262144 clks ~ 9.7 ms
    reg [7:0]  ch = 8'h41, data = 8'h41;
    reg        send = 1'b0;
    wire       busy;

    uart_tx #(.CLK_FREQ(27_000_000), .BAUD(115_200)) u (
        .clk(sys_clk), .rst_n(rst_n), .data(data), .send(send),
        .tx(uart_tx_pin), .busy(busy));

    always @(posedge sys_clk) begin
        tmr  <= tmr + 24'd1;
        send <= 1'b0;
        if (gap != 0) gap <= gap - 19'd1;
        else if (!busy && !send) begin
            data <= ch;
            send <= 1'b1;
            ch   <= (ch == 8'h5A) ? 8'h41 : ch + 8'd1;
            gap  <= 19'h3FFFF;
        end
    end
    assign led_alive = tmr[23];
endmodule
