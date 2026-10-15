module fir_filter_31tap_tm_triggered (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              start,       // pulse: a genuinely NEW sample is ready
    input  wire signed [15:0] sample_in,

    output wire signed [31:0] sample_out,
    output reg                out_valid,
    output reg                busy
);

    // ---- Control FSM: only runs a 31-tap pass when triggered ----
    localparam S_IDLE = 2'd0;
    localparam S_LOAD = 2'd1;
    localparam S_RUN  = 2'd2;

    reg [1:0] state;
    reg [4:0] tap;

    // ---- Shift register: shifts ONCE per triggered pass, right when 'start' fires ----
    reg signed [15:0] x0,x1,x2,x3,x4,x5,x6,x7,x8,x9,x10,x11,x12,x13,x14,x15;
    reg signed [15:0] x16,x17,x18,x19,x20,x21,x22,x23,x24,x25,x26,x27,x28,x29,x30;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            tap   <= 5'd0;
            busy  <= 1'b0;
            x0<=0;x1<=0;x2<=0;x3<=0;x4<=0;x5<=0;x6<=0;x7<=0;x8<=0;x9<=0;
            x10<=0;x11<=0;x12<=0;x13<=0;x14<=0;x15<=0;x16<=0;x17<=0;x18<=0;x19<=0;
            x20<=0;x21<=0;x22<=0;x23<=0;x24<=0;x25<=0;x26<=0;x27<=0;x28<=0;x29<=0;x30<=0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (start) begin
                        // consume the new sample right now, push everything else down
                        x0<=sample_in;
                        x1<=x0; x2<=x1; x3<=x2; x4<=x3; x5<=x4; x6<=x5; x7<=x6; x8<=x7; x9<=x8;
                        x10<=x9; x11<=x10; x12<=x11; x13<=x12; x14<=x13; x15<=x14; x16<=x15;
                        x17<=x16; x18<=x17; x19<=x18; x20<=x19; x21<=x20; x22<=x21; x23<=x22;
                        x24<=x23; x25<=x24; x26<=x25; x27<=x26; x28<=x27; x29<=x28; x30<=x29;
                        busy  <= 1'b1;
                        state <= S_LOAD;
                    end
                end

                S_LOAD: begin
                    // one cycle for the freshly-shifted x-registers to settle before
                    // the tap-0 multiply reads them
                    tap   <= 5'd0;
                    state <= S_RUN;
                end

                S_RUN: begin
                    if (tap == 5'd30) begin
                        busy  <= 1'b0;
                        state <= S_IDLE;
                    end else begin
                        tap <= tap + 5'd1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // ---- Coefficients (quantized, Q1.15 fixed-point) - unchanged ----
    localparam signed [15:0] h0=-16'sd178, h1=-16'sd180, h2=-16'sd100, h3=16'sd152, h4=16'sd590;
    localparam signed [15:0] h5=16'sd1036, h6=16'sd1137, h7=16'sd564, h8=-16'sd703, h9=-16'sd2213;
    localparam signed [15:0] h10=-16'sd3181, h11=-16'sd2903, h12=-16'sd1216, h13=16'sd1297, h14=16'sd3528;
    localparam signed [15:0] h15=16'sd4416, h16=16'sd3528, h17=16'sd1297, h18=-16'sd1216, h19=-16'sd2903;
    localparam signed [15:0] h20=-16'sd3181, h21=-16'sd2213, h22=-16'sd703, h23=16'sd564, h24=16'sd1137;
    localparam signed [15:0] h25=16'sd1036, h26=16'sd590, h27=16'sd152, h28=-16'sd100, h29=-16'sd180, h30=-16'sd178;

    // ---- Multiplexer: selects sample/coefficient pair for the current tap ----
    reg signed [15:0] current_x;
    reg signed [15:0] current_h;

    always @(*) begin
        case (tap)
            5'd0:  begin current_x = x0;  current_h = h0;  end
            5'd1:  begin current_x = x1;  current_h = h1;  end
            5'd2:  begin current_x = x2;  current_h = h2;  end
            5'd3:  begin current_x = x3;  current_h = h3;  end
            5'd4:  begin current_x = x4;  current_h = h4;  end
            5'd5:  begin current_x = x5;  current_h = h5;  end
            5'd6:  begin current_x = x6;  current_h = h6;  end
            5'd7:  begin current_x = x7;  current_h = h7;  end
            5'd8:  begin current_x = x8;  current_h = h8;  end
            5'd9:  begin current_x = x9;  current_h = h9;  end
            5'd10: begin current_x = x10; current_h = h10; end
            5'd11: begin current_x = x11; current_h = h11; end
            5'd12: begin current_x = x12; current_h = h12; end
            5'd13: begin current_x = x13; current_h = h13; end
            5'd14: begin current_x = x14; current_h = h14; end
            5'd15: begin current_x = x15; current_h = h15; end
            5'd16: begin current_x = x16; current_h = h16; end
            5'd17: begin current_x = x17; current_h = h17; end
            5'd18: begin current_x = x18; current_h = h18; end
            5'd19: begin current_x = x19; current_h = h19; end
            5'd20: begin current_x = x20; current_h = h20; end
            5'd21: begin current_x = x21; current_h = h21; end
            5'd22: begin current_x = x22; current_h = h22; end
            5'd23: begin current_x = x23; current_h = h23; end
            5'd24: begin current_x = x24; current_h = h24; end
            5'd25: begin current_x = x25; current_h = h25; end
            5'd26: begin current_x = x26; current_h = h26; end
            5'd27: begin current_x = x27; current_h = h27; end
            5'd28: begin current_x = x28; current_h = h28; end
            5'd29: begin current_x = x29; current_h = h29; end
            5'd30: begin current_x = x30; current_h = h30; end
            default: begin current_x = 16'sd0; current_h = 16'sd0; end
        endcase
    end

    // ---- Single multiplier, reused every cycle ----
    wire signed [31:0] mult_result;
    assign mult_result = current_x * current_h;

    // ---- Accumulator: builds up the sum over 31 cycles, only while running ----
    reg signed [36:0] accumulator;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            accumulator <= 37'sd0;
        else if (state == S_RUN) begin
            if (tap == 5'd0)
                accumulator <= mult_result;
            else
                accumulator <= accumulator + mult_result;
        end
    end

    // ---- Output valid flag: pulses once per completed pass ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            out_valid <= 1'b0;
        else
            out_valid <= (state == S_RUN) && (tap == 5'd30);
    end

    // ---- Final output, un-scaled ----
    assign sample_out = accumulator >>> 15;

endmodule
