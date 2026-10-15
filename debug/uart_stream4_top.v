// uart_stream4_top.v - A..Z stream + falling-edge counter on the TX line.
// Counts falling edges of uart_tx_pin over a 2^25-clock window (~1.24 s) and shows
// count[19:14] on the six LEDs (active-low, lit = 1). Left-to-right on the board:
// pin16 (bit19) pin15 pin14 pin13 pin11 pin10 (bit14).
module uart_stream4_top (
    input  wire sys_clk,
    output wire uart_tx_pin,
    output wire [5:0] led_n    // [5]=pin16 ... [0]=pin10
);
    reg [3:0] por = 4'd0;
    always @(posedge sys_clk) if (por != 4'hF) por <= por + 4'd1;
    wire rst_n = (por == 4'hF);

    reg [7:0] ch = 8'h41, data = 8'h41;
    reg send = 1'b0;
    wire busy;

    uart_tx #(.CLK_FREQ(27_000_000), .BAUD(115_200)) u (
        .clk(sys_clk), .rst_n(rst_n), .data(data), .send(send),
        .tx(uart_tx_pin), .busy(busy));

    always @(posedge sys_clk) begin
        send <= 1'b0;
        if (!busy && !send) begin
            data <= ch;
            send <= 1'b1;
            ch   <= (ch == 8'h5A) ? 8'h41 : ch + 8'd1;
        end
    end

    reg [24:0] win = 25'd0;
    reg [24:0] cnt = 25'd0;
    reg [5:0]  shown = 6'd0;
    reg prev = 1'b1;
    always @(posedge sys_clk) begin
        prev <= uart_tx_pin;
        win  <= win + 25'd1;
        if (win == 25'h1FFFFFF) begin
            shown <= cnt[19:14];
            cnt   <= 25'd0;
        end else if (prev && !uart_tx_pin)
            cnt <= cnt + 25'd1;
    end
    assign led_n = ~shown;
endmodule
