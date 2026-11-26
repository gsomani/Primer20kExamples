module LedChaser(input clk, output [3:0] led);
    localparam DIVIDER_BITS = 22;   // 2^22 / 27 MHz = ~155 ms per step

    reg [DIVIDER_BITS-1:0] divider = 0;
    reg [2:0] step = 0;
    reg [3:0] pattern;

    wire tick = &divider;

    always @(posedge clk) begin
        divider <= divider + 1;
        if (tick)
            step <= (step == 3'd5) ? 3'd0 : step + 3'd1;
    end

    // bounce: 0 1 2 3 2 1
    always @* begin
        case (step)
            3'd0:    pattern = 4'b0001;
            3'd1:    pattern = 4'b0010;
            3'd2:    pattern = 4'b0100;
            3'd3:    pattern = 4'b1000;
            3'd4:    pattern = 4'b0100;
            default: pattern = 4'b0010;
        endcase
    end

    assign led = ~pattern;          // LEDs are active low
endmodule
