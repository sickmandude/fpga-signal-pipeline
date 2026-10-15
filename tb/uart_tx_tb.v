`timescale 1ns/1ps
// uart_tx_tb.v
// Sends 5 bytes through uart_tx. An independent receiver model in this
// testbench watches the tx line and decodes it the way a real UART receiver
// would: find the falling edge, wait half a bit to land mid-start-bit, then
// sample once per bit period. All timing is done by counting clock edges
// (no $realtime), so there is no rounding.

module uart_tx_tb;

    localparam CLKS_PER_BIT = 27_000_000 / 115_200;   // 234

    reg        clk;
    reg        rst_n;
    reg  [7:0] data;
    reg        send;
    wire       tx;
    wire       busy;

    uart_tx uut (
        .clk   (clk),
        .rst_n (rst_n),
        .data  (data),
        .send  (send),
        .tx    (tx),
        .busy  (busy)
    );

    initial clk = 0;
    always #18.518 clk = ~clk;      // ~27 MHz

    // ---------- receiver model ----------
    reg [7:0] rx_byte;
    integer   i;
    integer   start_width;
    integer   errors;

    task receive_one;
        output [7:0] b;
        begin
            // wait for the line to fall (start bit)
            @(negedge tx);
            // measure the start bit width by counting clock edges until tx rises
            // or until we pass mid-bit: first just go to the middle of the start bit
            repeat (CLKS_PER_BIT / 2) @(posedge clk);
            if (tx !== 1'b0) begin
                $display("FAIL: start bit not low at mid-bit");
                errors = errors + 1;
            end
            // sample 8 data bits, one bit period apart, LSB first
            for (i = 0; i < 8; i = i + 1) begin
                repeat (CLKS_PER_BIT) @(posedge clk);
                b[i] = tx;
            end
            // stop bit
            repeat (CLKS_PER_BIT) @(posedge clk);
            if (tx !== 1'b1) begin
                $display("FAIL: stop bit not high");
                errors = errors + 1;
            end
        end
    endtask

    // ---------- driver ----------
    task send_byte;
        input [7:0] b;
        begin
            @(posedge clk);
            data <= b;
            send <= 1'b1;
            @(posedge clk);
            send <= 1'b0;
        end
    endtask

    reg [7:0] test_vals [0:4];
    integer   k;

    initial begin
        errors = 0;
        test_vals[0] = 8'h55;   // 01010101  - alternating, easy to see on a scope
        test_vals[1] = 8'hA3;
        test_vals[2] = 8'h00;   // all zeros
        test_vals[3] = 8'hFF;   // all ones
        test_vals[4] = 8'h81;   // only the two end bits set

        data  = 8'h00;
        send  = 1'b0;
        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        // the line must idle high
        if (tx !== 1'b1) begin
            $display("FAIL: tx not idle-high after reset");
            errors = errors + 1;
        end

        for (k = 0; k < 5; k = k + 1) begin
            fork
                send_byte(test_vals[k]);
                receive_one(rx_byte);
            join
            if (rx_byte === test_vals[k])
                $display("PASS byte %0d: sent 0x%02h, received 0x%02h", k, test_vals[k], rx_byte);
            else begin
                $display("FAIL byte %0d: sent 0x%02h, received 0x%02h", k, test_vals[k], rx_byte);
                errors = errors + 1;
            end
            // wait for the transmitter to finish before the next byte
            while (busy) @(posedge clk);
            repeat (10) @(posedge clk);
        end

        if (errors == 0) $display("ALL PASS");
        else             $display("%0d ERRORS", errors);
        $finish;
    end

endmodule
