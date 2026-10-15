`timescale 1ns/1ps

module fir_filter_31tap_tm_triggered_tb;

    reg clk;
    reg rst_n;
    reg start;
    reg signed [15:0] sample_in;
    wire signed [31:0] sample_out;
    wire out_valid;
    wire busy;

    fir_filter_31tap_tm_triggered uut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .sample_in(sample_in),
        .sample_out(sample_out),
        .out_valid(out_valid),
        .busy(busy)
    );

    always #5 clk = ~clk;

    // ---- Same seed=42 quantized input samples used for the free-running validation ----
    reg signed [15:0] test_samples [0:39];
    integer idx;

    initial begin
        test_samples[0]  = 16'sd4883;
        test_samples[1]  = 16'sd17901;
        test_samples[2]  = 16'sd32767;
        test_samples[3]  = 16'sd32767;
        test_samples[4]  = 16'sd16959;
        test_samples[5]  = -16'sd2302;
        test_samples[6]  = -16'sd3736;
        test_samples[7]  = -16'sd23620;
        test_samples[8]  = -16'sd32768;
        test_samples[9]  = -16'sd13927;
        test_samples[10] = -16'sd4556;
        test_samples[11] = 16'sd14682;
        test_samples[12] = 16'sd32767;
        test_samples[13] = 16'sd12356;
        test_samples[14] = 16'sd2304;
        test_samples[15] = -16'sd5528;
        test_samples[16] = -16'sd29217;
        test_samples[17] = -16'sd28075;
        test_samples[18] = -16'sd32768;
        test_samples[19] = -16'sd32768;
        test_samples[20] = 16'sd14408;
        test_samples[21] = 16'sd17041;
        test_samples[22] = 16'sd31828;
        test_samples[23] = 16'sd17158;
        test_samples[24] = 16'sd13909;
        test_samples[25] = 16'sd1090;
        test_samples[26] = -16'sd30575;
        test_samples[27] = -16'sd27471;
        test_samples[28] = -16'sd32768;
        test_samples[29] = -16'sd22128;
        test_samples[30] = -16'sd5915;
        test_samples[31] = 16'sd32767;
        test_samples[32] = 16'sd31032;
        test_samples[33] = 16'sd20766;
        test_samples[34] = 16'sd27346;
        test_samples[35] = -16'sd12001;
        test_samples[36] = -16'sd17207;
        test_samples[37] = -16'sd32768;
        test_samples[38] = -16'sd32768;
        test_samples[39] = -16'sd17325;
    end

    // ---- Drive one 'start' pulse per sample, waiting for the pass to finish ----
    // No fixed 310ns spacing needed anymore - we just wait for !busy, then go again.
    // This also proves the triggered version can accept back-to-back samples far
    // faster than the free-running version could, since it's not tied to any
    // fixed internal cadence.
    initial begin
        clk = 0;
        rst_n = 0;
        start = 0;
        idx = 0;
        sample_in = test_samples[0];

        #20 rst_n = 1;
        #10;

        for (idx = 0; idx < 40; idx = idx + 1) begin
            sample_in = test_samples[idx];
            @(posedge clk);
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;
            wait (busy == 1'b0);
        end

        #50;
        $finish;
    end

    always @(posedge clk) begin
        if (out_valid)
            $display("%0d", sample_out);
    end

endmodule
