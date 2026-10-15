// uart_pin_probe.v
// Pure combinational pin probe: pins 17 and 18 are INPUTS here, and each one is
// shown on an LED. The LEDs are active-low on this board, so
//   LED ON  = that pin is currently low
//   LED OFF = that pin is high (the idle level of a UART line)
//
// Use: have the Mac send a stream of 0x00 bytes (all-zero data = line held low
// for 9 of every 10 bit-times). The pin that the board's USB bridge drives
// will go low, and its LED will stay lit. Both pins are inputs, so the FPGA
// drives nothing and nothing can fight with the bridge chip.

module uart_pin_probe (
    input  wire pin_a,    // FPGA pin 17
    input  wire pin_b,    // FPGA pin 18
    output wire led_a,    // pin 16 LED (2nd from the left)
    output wire led_b     // pin 15 LED (3rd from the left)
);
    assign led_a = pin_a;
    assign led_b = pin_b;
endmodule
