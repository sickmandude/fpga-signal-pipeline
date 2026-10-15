module sample_rate_timer #(
    parameter CLK_FREQ    = 27_000_000,
    parameter SAMPLE_RATE = 10_000
)(
    input  wire clk,
    input  wire rst_n,
    output reg  tick   // pulses high for 1 cycle, once every (CLK_FREQ/SAMPLE_RATE) cycles
);

    localparam integer DIVIDER = CLK_FREQ / SAMPLE_RATE;  // 27,000,000 / 10,000 = 2700

    reg [31:0] count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= 32'd0;
            tick  <= 1'b0;
        end else if (count == DIVIDER - 1) begin
            count <= 32'd0;
            tick  <= 1'b1;
        end else begin
            count <= count + 32'd1;
            tick  <= 1'b0;
        end
    end

endmodule
