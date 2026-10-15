// uart_tx.v
// UART transmitter, 8 data bits, no parity, 1 stop bit (8N1), LSB first.
//
// Line idles HIGH. A frame is:
//   start bit (0) | D0 D1 D2 D3 D4 D5 D6 D7 | stop bit (1)
// Each bit lasts CLKS_PER_BIT system clock cycles.
//
// Usage: put a byte on `data`, pulse `send` high for ONE clock while `busy`
// is low. `busy` goes high the next cycle and stays high until the stop bit
// has finished. A `send` pulse while busy is ignored.

module uart_tx #(
    parameter CLK_FREQ = 27_000_000,
    parameter BAUD     = 115_200
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data,
    input  wire       send,
    output reg        tx,
    output reg        busy
);

    // Integer division: 27_000_000 / 115_200 = 234 (234.375 truncated).
    // Actual baud = 27e6/234 = 115_384.6, which is +0.16% from 115_200.
    localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD;

    localparam S_IDLE  = 2'd0;
    localparam S_START = 2'd1;
    localparam S_DATA  = 2'd2;
    localparam S_STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] clk_cnt;   // counts 0 .. CLKS_PER_BIT-1 within one bit
    reg [2:0]  bit_idx;   // which data bit (0..7) is currently on the line
    reg [7:0]  shreg;     // data being shifted out, LSB at shreg[0]

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            tx      <= 1'b1;
            busy    <= 1'b0;
            clk_cnt <= 16'd0;
            bit_idx <= 3'd0;
            shreg   <= 8'd0;
        end else begin
            case (state)

                S_IDLE: begin
                    tx      <= 1'b1;
                    busy    <= 1'b0;
                    clk_cnt <= 16'd0;
                    bit_idx <= 3'd0;
                    if (send) begin
                        shreg <= data;
                        busy  <= 1'b1;
                        tx    <= 1'b0;          // start bit begins now
                        state <= S_START;
                    end
                end

                S_START: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 16'd0;
                        tx      <= shreg[0];    // first data bit (D0)
                        state   <= S_DATA;
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end
                end

                S_DATA: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 16'd0;
                        if (bit_idx == 3'd7) begin
                            tx    <= 1'b1;      // stop bit
                            state <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 3'd1;
                            shreg   <= {1'b0, shreg[7:1]};  // drop the bit just sent
                            tx      <= shreg[1];            // next bit, becomes shreg[0]
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end
                end

                S_STOP: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 16'd0;
                        busy    <= 1'b0;
                        state   <= S_IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
