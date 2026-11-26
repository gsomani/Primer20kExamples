// MusicPlayer.v : slow, soothing sine melody over a swelling bass pad.
// Output: I2S to the PT8211 DAC on the Tang Primer 20K Dock.
// Pins (MusicPlayer.cst): clk H11, hpBck N15, hpWs P16, hpDin P15, paEn R16.

// Envelope: fast fade-in on trigger, then exponential decay.
// Updates once per audio sample (tick).
module Envelope #(
    parameter ATTACK_RATE = 262144,   // 2^28 / ATTACK_RATE samples to reach full level
    parameter DECAY_SHIFT = 15        // decay time constant = 2^DECAY_SHIFT samples
)(
    input clk,
    input tick,
    input trigger,
    output [15:0] level16
);
    reg [27:0] level = 0;
    reg attacking = 0;
    wire [28:0] nextUp = level + ATTACK_RATE;
    assign level16 = level[27:12];

    always @(posedge clk) if (tick) begin
        if (attacking) begin
            if (nextUp[28]) begin
                level <= 28'hFFFFFFF;
                attacking <= 0;
            end else
                level <= nextUp[27:0];
        end else
            level <= level - (level >> DECAY_SHIFT);
        if (trigger) attacking <= 1;
    end
endmodule

// Sine oscillator with envelope. Pipelined: the result is valid a few clocks
// after the phase changes, which is fine because phase only changes once per
// audio sample (every 512 clocks).
module SineVoice(
    input clk,
    input [31:0] phase,
    input [15:0] env,
    output reg signed [15:0] out
);
    // sine(pi*x) ~ 0.775*y + 0.225*y^2, where y = 4x(1-x), 1.0 = 16384
    wire [14:0] u = phase[30:16];                 // position within half period
    wire [31:0] uWide = {17'd0, u};

    reg [15:0] parab = 0;
    reg [15:0] sq = 0;
    reg [31:0] lin = 0, linDelayed = 0, sqScaled = 0;
    reg [15:0] sineMag = 0;
    reg neg1 = 0, neg2 = 0, neg3 = 0, neg4 = 0;

    wire [31:0] parabWide = {16'd0, parab};
    wire [31:0] sqWide    = {16'd0, sq};

    wire signed [16:0] sineSigned =
        neg4 ? -$signed({1'b0, sineMag}) : $signed({1'b0, sineMag});
    wire signed [34:0] prod = sineSigned * $signed({1'b0, env});

    always @(posedge clk) begin
        parab       <= (uWide * (32'd32768 - uWide)) >> 14;   // stage 1
        neg1        <= phase[31];

        sq          <= (parabWide * parabWide) >> 14;         // stage 2
        lin         <= parabWide * 32'd12698;
        neg2        <= neg1;

        sqScaled    <= sqWide * 32'd3686;                     // stage 3
        linDelayed  <= lin;
        neg3        <= neg2;

        sineMag     <= (linDelayed + sqScaled) >> 14;         // stage 4
        neg4        <= neg3;

        out         <= prod >>> 16;                           // stage 5
    end
endmodule

module MusicPlayer(
    input clk,
    output reg hpBck = 0,
    output reg hpWs = 0,
    output reg hpDin = 0,
    output paEn
);
    localparam PHASE_PER_HZ = 81445;        // 2^32 / 52734.4 Hz sample rate
    localparam STEP_FRAMES  = 26367;        // 0.5 s per step (use 39550 for 0.75 s)
    localparam MASTER_SHIFT = 4;            // volume: lower = louder (3 = 2x, 2 = 4x)
    localparam MELODY_OCTAVES_DOWN = 0;     // 1 = melody one octave lower

    // Melody: 16 steps per chord row, written in playing order (step 0 on the left).
    // 0 = hold the previous note, 1..8 = C4 D4 E4 G4 A4 C5 D5 E5
    function [3:0] melodyNoteAt(input [5:0] s);
        reg [63:0] row;
        begin
            case (s[5:4])
                2'd0:    row = 64'h5006800060504000;   // Am
                2'd1:    row = 64'h4050600050403000;   // F
                2'd2:    row = 64'h3040600080064000;   // C
                default: row = 64'h2040500070605000;   // G
            endcase
            melodyNoteAt = row[{~s[3:0], 2'b00} +: 4];
        end
    endfunction

    function [31:0] melodyIncOf(input [3:0] n);
        case (n)
            4'd1:    melodyIncOf = 262 * PHASE_PER_HZ;
            4'd2:    melodyIncOf = 294 * PHASE_PER_HZ;
            4'd3:    melodyIncOf = 330 * PHASE_PER_HZ;
            4'd4:    melodyIncOf = 392 * PHASE_PER_HZ;
            4'd5:    melodyIncOf = 440 * PHASE_PER_HZ;
            4'd6:    melodyIncOf = 523 * PHASE_PER_HZ;
            4'd7:    melodyIncOf = 587 * PHASE_PER_HZ;
            default: melodyIncOf = 659 * PHASE_PER_HZ;
        endcase
    endfunction

    // chord roots: Am F C G  (A2 F2 C3 G2)
    function [31:0] bassIncOf(input [1:0] c);
        case (c)
            2'd0:    bassIncOf = 110 * PHASE_PER_HZ;
            2'd1:    bassIncOf = 87  * PHASE_PER_HZ;
            2'd2:    bassIncOf = 131 * PHASE_PER_HZ;
            default: bassIncOf = 98  * PHASE_PER_HZ;
        endcase
    endfunction

    assign paEn = 1'b1;

    // ---- I2S timing ----
    reg [2:0] bckDiv = 0;
    reg [4:0] slotBit = 0;
    wire bckTick  = (bckDiv == 3'd7);                         // BCK = 27 MHz / 16
    wire frameEnd = bckTick && hpBck && (slotBit == 5'd31);   // once per sample

    // ---- song state ----
    reg [14:0] frameCount = 0;
    reg [5:0]  step = 0;
    wire [5:0] nextStep = step + 6'd1;
    wire [3:0] nextNote = melodyNoteAt(nextStep);
    wire stepEnd = (frameCount == STEP_FRAMES - 1);

    reg [31:0] melodyInc = 440 * PHASE_PER_HZ;
    reg [31:0] bassInc   = 110 * PHASE_PER_HZ;
    reg [31:0] melodyPhase = 0;
    reg [31:0] bassPhase = 0;
    reg melodyTrig = 1;
    reg bassTrig = 1;

    wire [15:0] melodyEnv, bassEnv;
    wire signed [15:0] melodyOut, bassOut;

    Envelope #(.ATTACK_RATE(262144), .DECAY_SHIFT(15))
        melodyEnvelope(.clk(clk), .tick(frameEnd), .trigger(melodyTrig), .level16(melodyEnv));
    Envelope #(.ATTACK_RATE(8192), .DECAY_SHIFT(17))
        bassEnvelope(.clk(clk), .tick(frameEnd), .trigger(bassTrig), .level16(bassEnv));

    SineVoice melodyVoice(.clk(clk), .phase(melodyPhase), .env(melodyEnv), .out(melodyOut));
    SineVoice bassVoice(.clk(clk), .phase(bassPhase), .env(bassEnv), .out(bassOut));

    wire signed [17:0] mix = melodyOut + (bassOut >>> 1);
    reg signed [15:0] sample = 0;

    always @(posedge clk) begin
        bckDiv <= bckDiv + 1;

        if (bckTick) begin
            hpBck <= ~hpBck;
            if (hpBck) begin                          // falling edge: change WS and data
                hpWs    <= slotBit[4];
                hpDin   <= sample[~slotBit[3:0]];     // MSB first, 16 bits per channel
                slotBit <= slotBit + 1;
            end
        end

        if (frameEnd) begin
            melodyPhase <= melodyPhase + (melodyInc >> MELODY_OCTAVES_DOWN);
            bassPhase   <= bassPhase + bassInc;
            sample      <= mix >>> MASTER_SHIFT;

            melodyTrig <= 0;                          // triggers last one frame
            bassTrig   <= 0;
            if (stepEnd) begin
                frameCount <= 0;
                step <= nextStep;
                if (nextNote != 4'd0) begin
                    melodyInc  <= melodyIncOf(nextNote);
                    melodyTrig <= 1;
                end
                if (nextStep[3:0] == 4'd0) begin      // new chord every 16 steps (8 s)
                    bassInc  <= bassIncOf(nextStep[5:4]);
                    bassTrig <= 1;
                end
            end else
                frameCount <= frameCount + 1;
        end
    end
endmodule
