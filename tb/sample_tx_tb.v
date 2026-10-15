`timescale 1ns/1ps
// sample_tx_tb.v
// Feeds 4 fake "filtered sample" pulses into sample_tx with DECIM=2, so only
// the 2nd and 4th are transmitted. An independent UART receiver model decodes
// the tx line and the 14 received bytes are compared against frames computed
// separately in Python:
//   sample 2: filtered=-277,   adc_raw=640 -> AA FF FE EB 02 80 68
//   sample 4: filtered=-42372, adc_raw=0   -> AA FF 5A 7C 00 00 D9

module sample_tx_tb;

    localparam CLKS_PER_BIT = 27_000_000 / 115_200;   // 234

    reg               clk;
    reg               rst_n;
    reg               valid;
    reg signed [31:0] filtered;
    reg        [9:0]  adc_raw;
    wire              tx;

    sample_tx #(.DECIM(2)) uut (
        .clk      (clk),
        .rst_n    (rst_n),
        .valid    (valid),
        .filtered (filtered),
        .adc_raw  (adc_raw),
        .tx       (tx)
    );

    initial clk = 0;
    always #18.518 clk = ~clk;      // ~27 MHz

    // ---------- UART receiver model (runs forever, collects bytes) ----------
    reg [7:0] rx_buf [0:31];
    integer   rx_count;
    integer   bi;
    reg [7:0] rb;

    initial rx_count = 0;

    always begin
        @(negedge tx);                              // start bit begins
        repeat (CLKS_PER_BIT / 2) @(posedge clk);   // middle of the start bit
        for (bi = 0; bi < 8; bi = bi + 1) begin
            repeat (CLKS_PER_BIT) @(posedge clk);
            rb[bi] = tx;
        end
        repeat (CLKS_PER_BIT) @(posedge clk);       // middle of the stop bit
        if (tx !== 1'b1) $display("FAIL: stop bit not high on byte %0d", rx_count);
        rx_buf[rx_count] = rb;
        rx_count = rx_count + 1;
    end

    // ---------- stimulus ----------
    task push_sample;
        input signed [31:0] f;
        input        [9:0]  r;
        begin
            @(posedge clk);
            filtered <= f;
            adc_raw  <= r;
            valid    <= 1'b1;
            @(posedge clk);
            valid    <= 1'b0;
            repeat (20000) @(posedge clk);   // far longer than one 7-byte frame
        end
    endtask

    reg [7:0] expected [0:13];
    integer   n;
    integer   errors;

    initial begin
        expected[0]  = 8'hAA; expected[1]  = 8'hFF; expected[2]  = 8'hFE;
        expected[3]  = 8'hEB; expected[4]  = 8'h02; expected[5]  = 8'h80;
        expected[6]  = 8'h68;
        expected[7]  = 8'hAA; expected[8]  = 8'hFF; expected[9]  = 8'h5A;
        expected[10] = 8'h7C; expected[11] = 8'h00; expected[12] = 8'h00;
        expected[13] = 8'hD9;

        errors   = 0;
        valid    = 1'b0;
        filtered = 32'sd0;
        adc_raw  = 10'd0;
        rst_n    = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        push_sample(-98,    10'd700);    // 1st: skipped by decimation
        push_sample(-277,   10'd640);    // 2nd: sent
        push_sample(12345,  10'd1023);   // 3rd: skipped
        push_sample(-42372, 10'd0);      // 4th: sent
        repeat (20000) @(posedge clk);

        if (rx_count !== 14) begin
            $display("FAIL: received %0d bytes, expected 14", rx_count);
            errors = errors + 1;
        end
        for (n = 0; n < 14; n = n + 1) begin
            if (rx_buf[n] === expected[n])
                $display("PASS byte %0d: 0x%02h", n, rx_buf[n]);
            else begin
                $display("FAIL byte %0d: got 0x%02h expected 0x%02h", n, rx_buf[n], expected[n]);
                errors = errors + 1;
            end
        end

        if (errors == 0) $display("ALL PASS");
        else             $display("%0d ERRORS", errors);
        $finish;
    end

endmodule
