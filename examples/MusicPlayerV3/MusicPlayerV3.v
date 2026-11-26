module MusicPlayerV3(
    input clk,
    output reg hpBck = 0,
    output reg hpWs = 0,
    output reg hpDin = 0,
    output paEn
);

    localparam OCTAVES_DOWN = 1;   // 0 = original pitch, 1 = one octave lower, 2 = two lower
    // Quiet on purpose: the amp can be loud (full scale is 32767)
    localparam signed [15:0] AMPLITUDE = 16'sd1024;

    // Sample rate = 27 MHz / 16 / 32 = 52734.4 Hz
    // phase increment = freq * 2^32 / 52734.4 = freq * 81445
    localparam [31:0] NOTE_C4 = 262 * 81445;
    localparam [31:0] NOTE_D4 = 294 * 81445;
    localparam [31:0] NOTE_E4 = 330 * 81445;
    localparam [31:0] NOTE_F4 = 349 * 81445;
    localparam [31:0] NOTE_G4 = 392 * 81445;
    localparam [31:0] NOTE_A4 = 440 * 81445;

    assign paEn = 1'b1;                       // amplifier enable

    reg [2:0]  bckDiv = 0;
    reg [4:0]  slotBit = 0;                   // 0..15 left slot, 16..31 right slot
    reg [31:0] phase = 0;
    reg [31:0] phaseInc;
    reg signed [15:0] sample = 0;
    reg [22:0] beatTimer = 0;                 // 2^23 / 27 MHz = 0.31 s per note
    reg [3:0]  step = 0;

    wire bckTick = (bckDiv == 3'd7);          // BCK = 27 MHz / 16
    wire gap     = (beatTimer[22:20] == 3'b111);

    always @* begin
        case (step)
            4'd0,  4'd1:  phaseInc = NOTE_C4;
            4'd2,  4'd3:  phaseInc = NOTE_G4;
            4'd4,  4'd5:  phaseInc = NOTE_A4;
            4'd6,  4'd7:  phaseInc = NOTE_G4;
            4'd8,  4'd9:  phaseInc = NOTE_F4;
            4'd10, 4'd11: phaseInc = NOTE_E4;
            4'd12, 4'd13: phaseInc = NOTE_D4;
            default:      phaseInc = NOTE_C4;
        endcase
    end

    always @(posedge clk) begin
        bckDiv    <= bckDiv + 1;
        beatTimer <= beatTimer + 1;
        if (&beatTimer) step <= step + 1;

        if (bckTick) begin
            hpBck <= ~hpBck;
            if (hpBck) begin                  // falling edge: change WS and data
                hpWs    <= slotBit[4];
                hpDin   <= sample[~slotBit[3:0]];   // MSB first, 16 bits per channel
                slotBit <= slotBit + 1;
                if (slotBit == 5'd31) begin   // once per frame: next sample
                    phase  <= phase + (phaseInc >> OCTAVES_DOWN);
                    sample <= gap ? 16'sd0 : (phase[31] ? AMPLITUDE : -AMPLITUDE);
                end
            end
        end
    end
endmodule
