// sample_tx.v
// Turns each (decimated) filtered sample into a 7-byte frame and sends it
// out over a UART.
//
// Frame (bytes sent in this order):
//   0: 0xAA                       sync marker
//   1: filtered[23:16]            24-bit signed filter output, big-endian
//   2: filtered[15:8]
//   3: filtered[7:0]
//   4: {6'b0, adc_raw[9:8]}       raw 10-bit ADC code, big-endian
//   5: adc_raw[7:0]
//   6: XOR of bytes 1..5          checksum
//
// Why 24 bits and not 32: the filter's output is at most about +/-42,372
// (sum of |coefficients|), which needs 17 bits signed. 24 bits is plenty and
// the top byte of the 32-bit sample is always just sign extension.
//
// Why decimate: at 115,200 baud a 7-byte frame takes 70 bit-times, so at most
// ~1,645 frames/s fit on the wire. The filter produces 10,000 samples/s, so
// only every DECIM-th sample is sent. This does NOT affect the filtering; it
// only limits how many results are reported to the PC.

module sample_tx #(
    parameter CLK_FREQ = 27_000_000,
    parameter BAUD     = 115_200,
    parameter DECIM    = 8
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              valid,         // 1-cycle pulse: new filtered sample
    input  wire signed [31:0] filtered,
    input  wire        [9:0] adc_raw,
    output wire              tx
);

    // ---- the byte-level transmitter ----
    reg  [7:0] uart_data;
    reg        uart_send;
    wire       uart_busy;

    uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD(BAUD)) u_uart (
        .clk   (clk),
        .rst_n (rst_n),
        .data  (uart_data),
        .send  (uart_send),
        .tx    (tx),
        .busy  (uart_busy)
    );

    // ---- decimation counter: counts every valid pulse ----
    reg [15:0] dec_cnt;

    // ---- latched copy of the sample being sent ----
    reg [23:0] f_lat;
    reg  [9:0] r_lat;

    wire [7:0] chk = f_lat[23:16] ^ f_lat[15:8] ^ f_lat[7:0] ^
                     {6'b0, r_lat[9:8]} ^ r_lat[7:0];

    // ---- frame sequencer ----
    localparam S_IDLE = 2'd0;
    localparam S_LOAD = 2'd1;   // put byte on uart_data, raise uart_send
    localparam S_WAIT = 2'd2;   // uart_send is high this cycle; drop it
    localparam S_BUSY = 2'd3;   // wait for the byte to finish

    reg [1:0] state;
    reg [2:0] idx;              // which byte of the frame (0..6)

    reg [7:0] cur_byte;
    always @(*) begin
        case (idx)
            3'd0:    cur_byte = 8'hAA;
            3'd1:    cur_byte = f_lat[23:16];
            3'd2:    cur_byte = f_lat[15:8];
            3'd3:    cur_byte = f_lat[7:0];
            3'd4:    cur_byte = {6'b0, r_lat[9:8]};
            3'd5:    cur_byte = r_lat[7:0];
            default: cur_byte = chk;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            idx       <= 3'd0;
            dec_cnt   <= 16'd0;
            f_lat     <= 24'd0;
            r_lat     <= 10'd0;
            uart_data <= 8'd0;
            uart_send <= 1'b0;
        end else begin
            uart_send <= 1'b0;   // default: a one-cycle pulse only

            // count every valid pulse; every DECIM-th one starts a frame
            if (valid) begin
                if (dec_cnt == DECIM - 1) begin
                    dec_cnt <= 16'd0;
                    if (state == S_IDLE) begin
                        f_lat <= filtered[23:0];
                        r_lat <= adc_raw;
                        idx   <= 3'd0;
                        state <= S_LOAD;
                    end
                    // else: previous frame still going out -> this sample is skipped
                end else begin
                    dec_cnt <= dec_cnt + 16'd1;
                end
            end

            case (state)
                S_LOAD: begin
                    if (!uart_busy) begin
                        uart_data <= cur_byte;
                        uart_send <= 1'b1;
                        state     <= S_WAIT;
                    end
                end

                S_WAIT: begin
                    // uart_send is high during this cycle and gets sampled
                    // by uart_tx at the end of it; busy rises right after
                    state <= S_BUSY;
                end

                S_BUSY: begin
                    if (!uart_busy) begin
                        if (idx == 3'd6) begin
                            state <= S_IDLE;
                        end else begin
                            idx   <= idx + 3'd1;
                            state <= S_LOAD;
                        end
                    end
                end

                default: ;   // S_IDLE: nothing to do, waiting for a valid pulse
            endcase
        end
    end

endmodule
