`timescale 1ns/1ps

module adc_fir_top_tb;

    reg  sys_clk;
    reg  sys_rst_n;
    wire adc_sclk, adc_cs_n, adc_mosi;
    reg  adc_miso;
    wire signed [31:0] filtered_sample;
    wire filtered_valid;

    adc_fir_top uut (
        .sys_clk         (sys_clk),
        .sys_rst_n       (sys_rst_n),
        .adc_sclk        (adc_sclk),
        .adc_cs_n        (adc_cs_n),
        .adc_mosi        (adc_mosi),
        .adc_miso        (adc_miso),
        .filtered_sample (filtered_sample),
        .filtered_valid  (filtered_valid)
    );

    // 27 MHz system clock
    initial sys_clk = 0;
    always #18.518 sys_clk = ~sys_clk;

    // ---- Fake MCP3008: plays back a pre-chosen 10-bit code for each
    //      successive conversion, matching full_chain_model.py's
    //      adc_code_from_signal_fixed() values for the first 20
    //      seed=42 samples ----
    reg [9:0] adc_codes [0:19];
    integer   conv_idx;
    integer   edge_count;
    reg [9:0] current_code;

    initial begin
        adc_codes[0]=588;  adc_codes[1]=792;  adc_codes[2]=1023; adc_codes[3]=1023; adc_codes[4]=777;
        adc_codes[5]=476;  adc_codes[6]=454;  adc_codes[7]=143;  adc_codes[8]=0;    adc_codes[9]=294;
        adc_codes[10]=441; adc_codes[11]=741; adc_codes[12]=1023;adc_codes[13]=705; adc_codes[14]=548;
        adc_codes[15]=426; adc_codes[16]=55;  adc_codes[17]=73;  adc_codes[18]=0;   adc_codes[19]=0;
    end

    initial begin
        conv_idx  = -1;
        edge_count = 0;
        adc_miso  = 1'b0;
    end

    // a new conversion starts every time CS drops - pick the next code
    always @(negedge adc_cs_n) begin
        conv_idx   = conv_idx + 1;
        edge_count = 0;
        if (conv_idx < 20)
            current_code = adc_codes[conv_idx];
        else
            current_code = 10'd0;
    end

    always @(posedge adc_sclk) begin
        edge_count = edge_count + 1;
    end

    // present bits on falling edges, exactly like the real chip (and the
    // standalone SPI testbench that already validated this timing)
    always @(negedge adc_sclk) begin
        if (edge_count == 6)
            adc_miso <= 1'b0;
        else if (edge_count >= 7 && edge_count <= 16)
            adc_miso <= (current_code >> (9 - (edge_count - 7))) & 10'b1;
    end

    // ---- Run long enough to see all 20 filtered outputs ----
    // Each ADC sample takes 2700 system-clock cycles (10kHz); add margin
    // for reset and pipeline fill.
    initial begin
        sys_rst_n = 0;
        repeat (5) @(posedge sys_clk);
        sys_rst_n = 1;

        repeat (20 * 2700 + 5000) @(posedge sys_clk);

        $display("Simulation complete.");
        $finish;
    end

    always @(posedge sys_clk) begin
        if (filtered_valid)
            $display("%0d", filtered_sample);
    end

endmodule
