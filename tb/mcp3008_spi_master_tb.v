`timescale 1ns/1ps

module mcp3008_spi_master_tb;

    reg         clk;
    reg         rst_n;
    reg         start;
    reg  [2:0]  channel;
    wire        sclk;
    wire        cs_n;
    wire        mosi;
    reg         miso;
    wire [9:0]  adc_data;
    wire        data_valid;
    wire        busy;

    mcp3008_spi_master #(.SCLK_DIV(14)) uut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .channel(channel),
        .sclk(sclk),
        .cs_n(cs_n),
        .mosi(mosi),
        .miso(miso),
        .adc_data(adc_data),
        .data_valid(data_valid),
        .busy(busy)
    );

    // ---- 27 MHz system clock (~37.037ns period, matches the Tang Nano 9K) ----
    initial clk = 0;
    always #18.518 clk = ~clk;

    // ---- Fake MCP3008: plays back a chosen 10-bit value on MISO,
    //      exactly the way a real chip would present it on falling edges ----
    reg [9:0] fake_adc_value;
    integer   edge_count;

    initial begin
        edge_count = 0;
        miso = 1'b0;
    end

    // reset the bit counter whenever CS goes low (start of a new transaction)
    always @(negedge cs_n) begin
        edge_count = 0;
    end

    // count rising edges of SCLK (1-indexed, matching the datasheet's 17-clock protocol)
    always @(posedge sclk) begin
        edge_count = edge_count + 1;
    end

    // present the next bit on the falling edge that follows, just like a real chip
    always @(negedge sclk) begin
        if (edge_count == 6)
            miso <= 1'b0;  // null bit, ready ahead of the 7th rising edge
        else if (edge_count >= 7 && edge_count <= 16)
            miso <= (fake_adc_value >> (9 - (edge_count - 7))) & 10'b1;
    end

    // ---- Task: run one conversion and check the result ----
    task run_conversion(input [2:0] ch, input [9:0] fake_value);
        begin
            fake_adc_value = fake_value;
            channel        = ch;
            @(posedge clk);
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;

            wait (data_valid == 1'b1);
            #1; // let adc_data settle in the waveform/print

            if (adc_data === fake_value)
                $display("PASS  channel=%0d  expected=%0d (0x%03X)  got=%0d (0x%03X)",
                          ch, fake_value, fake_value, adc_data, adc_data);
            else
                $display("FAIL  channel=%0d  expected=%0d (0x%03X)  got=%0d (0x%03X)",
                          ch, fake_value, fake_value, adc_data, adc_data);

            @(posedge clk);
        end
    endtask

    initial begin
        rst_n = 0;
        start = 0;
        channel = 3'd0;
        fake_adc_value = 10'd0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        run_conversion(3'd3, 10'd691);   // 0x2B3
        run_conversion(3'd5, 10'd341);   // 0x155
        run_conversion(3'd0, 10'd1023);  // 0x3FF, all-ones edge case
        run_conversion(3'd7, 10'd0);     // channel 7, all-zeros edge case

        $display("All conversions complete.");
        $finish;
    end

endmodule
