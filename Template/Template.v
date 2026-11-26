// Starter design: 27 MHz clock input, one LED. Replace with your own logic.
module Template(
    input clk,
    output led
);
    reg [24:0] counter = 0;
    always @(posedge clk) counter <= counter + 1;
    assign led = ~counter[24];
endmodule
