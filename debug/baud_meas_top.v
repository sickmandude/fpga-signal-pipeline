// baud_meas_top.v - measures the real bit time the USB bridge uses on pin 18.
// Mac sends 'U' (0x55): every low pulse is exactly one bit time.
// LEDs show (width_in_27MHz_clocks >> 2), 6 bits, saturating at 63 (width >= 252).
// Leftmost of the six = MSB. Lit = 1. Expected for 115200 baud: width 234 -> 58 = 111010.
module baud_meas_top (
    input  wire sys_clk,
    input  wire rx_pin,          // pin 18
    output wire [5:0] led_n      // [5]=pin16 ... [0]=pin10
);
    reg s0 = 1'b1, s1 = 1'b1, prev = 1'b1;
    reg [15:0] cnt = 16'd0;
    reg [15:0] last = 16'd0;
    always @(posedge sys_clk) begin
        s0 <= rx_pin; s1 <= s0; prev <= s1;
        if (!s1) begin
            if (cnt != 16'hFFFF) cnt <= cnt + 16'd1;
        end else begin
            if (!prev) last <= cnt;      // rising edge: latch the low-pulse width
            cnt <= 16'd0;
        end
    end
    wire [5:0] shown = (last[15:8] != 0) ? 6'd63 : last[7:2];
    assign led_n = ~shown;
endmodule
