// echo_top.v - wires FPGA RX (pin 18) straight to FPGA TX (pin 17).
// Whatever the Mac sends should come straight back. LED 16 shows RX activity.
module echo_top (
    input  wire sys_clk,
    input  wire uart_rx_pin,   // pin 18, driven by the bridge
    output wire uart_tx_pin,   // pin 17, goes to the bridge
    output wire led_rx         // pin 16, active-low: lit when line is low
);
    assign uart_tx_pin = uart_rx_pin;
    assign led_rx = uart_rx_pin;
endmodule
