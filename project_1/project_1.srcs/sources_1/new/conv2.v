`timescale 1ns / 1ps
// ============================================================
// conv2.v  - Conv Layer 2
// 16ch → 32ch, 3×3, padding=same
// 입력 : BRAM (12×12×16)  출력 : BRAM (12×12×32, ReLU)
//
// weight 1D: wflat[N*32 + oc],  N = ic*9+k  (0~143)
// 총 144×32 = 4608값
// ============================================================

module conv2 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,

    output reg  [11:0] ibram_addr,   // 12×12×16=2304
    input  wire [7:0]  ibram_rdata,

    output reg  [12:0] obram_addr,   // 12×12×32=4608 → 13-bit
    output reg  [7:0]  obram_wdata,
    output reg         obram_we,

    output reg         done
);

localparam IN_H  = 12;
localparam IN_W  = 12;
localparam IN_CH = 16;
localparam OUT_H = 12;
localparam OUT_W = 12;
localparam N_OCH = 32;

// ── Weight 1D: [N*32 + oc] ───────────────────────────────────
reg signed [7:0]  wflat [0:4607];
reg signed [15:0] bias  [0:31];

initial begin
    $readmemh("conv2_weight_0.txt",   wflat,    0,   31);
    $readmemh("conv2_weight_1.txt",   wflat,   32,   63);
    $readmemh("conv2_weight_2.txt",   wflat,   64,   95);
    $readmemh("conv2_weight_3.txt",   wflat,   96,  127);
    $readmemh("conv2_weight_4.txt",   wflat,  128,  159);
    $readmemh("conv2_weight_5.txt",   wflat,  160,  191);
    $readmemh("conv2_weight_6.txt",   wflat,  192,  223);
    $readmemh("conv2_weight_7.txt",   wflat,  224,  255);
    $readmemh("conv2_weight_8.txt",   wflat,  256,  287);
    $readmemh("conv2_weight_9.txt",   wflat,  288,  319);
    $readmemh("conv2_weight_10.txt",  wflat,  320,  351);
    $readmemh("conv2_weight_11.txt",  wflat,  352,  383);
    $readmemh("conv2_weight_12.txt",  wflat,  384,  415);
    $readmemh("conv2_weight_13.txt",  wflat,  416,  447);
    $readmemh("conv2_weight_14.txt",  wflat,  448,  479);
    $readmemh("conv2_weight_15.txt",  wflat,  480,  511);
    $readmemh("conv2_weight_16.txt",  wflat,  512,  543);
    $readmemh("conv2_weight_17.txt",  wflat,  544,  575);
    $readmemh("conv2_weight_18.txt",  wflat,  576,  607);
    $readmemh("conv2_weight_19.txt",  wflat,  608,  639);
    $readmemh("conv2_weight_20.txt",  wflat,  640,  671);
    $readmemh("conv2_weight_21.txt",  wflat,  672,  703);
    $readmemh("conv2_weight_22.txt",  wflat,  704,  735);
    $readmemh("conv2_weight_23.txt",  wflat,  736,  767);
    $readmemh("conv2_weight_24.txt",  wflat,  768,  799);
    $readmemh("conv2_weight_25.txt",  wflat,  800,  831);
    $readmemh("conv2_weight_26.txt",  wflat,  832,  863);
    $readmemh("conv2_weight_27.txt",  wflat,  864,  895);
    $readmemh("conv2_weight_28.txt",  wflat,  896,  927);
    $readmemh("conv2_weight_29.txt",  wflat,  928,  959);
    $readmemh("conv2_weight_30.txt",  wflat,  960,  991);
    $readmemh("conv2_weight_31.txt",  wflat,  992, 1023);
    $readmemh("conv2_weight_32.txt",  wflat, 1024, 1055);
    $readmemh("conv2_weight_33.txt",  wflat, 1056, 1087);
    $readmemh("conv2_weight_34.txt",  wflat, 1088, 1119);
    $readmemh("conv2_weight_35.txt",  wflat, 1120, 1151);
    $readmemh("conv2_weight_36.txt",  wflat, 1152, 1183);
    $readmemh("conv2_weight_37.txt",  wflat, 1184, 1215);
    $readmemh("conv2_weight_38.txt",  wflat, 1216, 1247);
    $readmemh("conv2_weight_39.txt",  wflat, 1248, 1279);
    $readmemh("conv2_weight_40.txt",  wflat, 1280, 1311);
    $readmemh("conv2_weight_41.txt",  wflat, 1312, 1343);
    $readmemh("conv2_weight_42.txt",  wflat, 1344, 1375);
    $readmemh("conv2_weight_43.txt",  wflat, 1376, 1407);
    $readmemh("conv2_weight_44.txt",  wflat, 1408, 1439);
    $readmemh("conv2_weight_45.txt",  wflat, 1440, 1471);
    $readmemh("conv2_weight_46.txt",  wflat, 1472, 1503);
    $readmemh("conv2_weight_47.txt",  wflat, 1504, 1535);
    $readmemh("conv2_weight_48.txt",  wflat, 1536, 1567);
    $readmemh("conv2_weight_49.txt",  wflat, 1568, 1599);
    $readmemh("conv2_weight_50.txt",  wflat, 1600, 1631);
    $readmemh("conv2_weight_51.txt",  wflat, 1632, 1663);
    $readmemh("conv2_weight_52.txt",  wflat, 1664, 1695);
    $readmemh("conv2_weight_53.txt",  wflat, 1696, 1727);
    $readmemh("conv2_weight_54.txt",  wflat, 1728, 1759);
    $readmemh("conv2_weight_55.txt",  wflat, 1760, 1791);
    $readmemh("conv2_weight_56.txt",  wflat, 1792, 1823);
    $readmemh("conv2_weight_57.txt",  wflat, 1824, 1855);
    $readmemh("conv2_weight_58.txt",  wflat, 1856, 1887);
    $readmemh("conv2_weight_59.txt",  wflat, 1888, 1919);
    $readmemh("conv2_weight_60.txt",  wflat, 1920, 1951);
    $readmemh("conv2_weight_61.txt",  wflat, 1952, 1983);
    $readmemh("conv2_weight_62.txt",  wflat, 1984, 2015);
    $readmemh("conv2_weight_63.txt",  wflat, 2016, 2047);
    $readmemh("conv2_weight_64.txt",  wflat, 2048, 2079);
    $readmemh("conv2_weight_65.txt",  wflat, 2080, 2111);
    $readmemh("conv2_weight_66.txt",  wflat, 2112, 2143);
    $readmemh("conv2_weight_67.txt",  wflat, 2144, 2175);
    $readmemh("conv2_weight_68.txt",  wflat, 2176, 2207);
    $readmemh("conv2_weight_69.txt",  wflat, 2208, 2239);
    $readmemh("conv2_weight_70.txt",  wflat, 2240, 2271);
    $readmemh("conv2_weight_71.txt",  wflat, 2272, 2303);
    $readmemh("conv2_weight_72.txt",  wflat, 2304, 2335);
    $readmemh("conv2_weight_73.txt",  wflat, 2336, 2367);
    $readmemh("conv2_weight_74.txt",  wflat, 2368, 2399);
    $readmemh("conv2_weight_75.txt",  wflat, 2400, 2431);
    $readmemh("conv2_weight_76.txt",  wflat, 2432, 2463);
    $readmemh("conv2_weight_77.txt",  wflat, 2464, 2495);
    $readmemh("conv2_weight_78.txt",  wflat, 2496, 2527);
    $readmemh("conv2_weight_79.txt",  wflat, 2528, 2559);
    $readmemh("conv2_weight_80.txt",  wflat, 2560, 2591);
    $readmemh("conv2_weight_81.txt",  wflat, 2592, 2623);
    $readmemh("conv2_weight_82.txt",  wflat, 2624, 2655);
    $readmemh("conv2_weight_83.txt",  wflat, 2656, 2687);
    $readmemh("conv2_weight_84.txt",  wflat, 2688, 2719);
    $readmemh("conv2_weight_85.txt",  wflat, 2720, 2751);
    $readmemh("conv2_weight_86.txt",  wflat, 2752, 2783);
    $readmemh("conv2_weight_87.txt",  wflat, 2784, 2815);
    $readmemh("conv2_weight_88.txt",  wflat, 2816, 2847);
    $readmemh("conv2_weight_89.txt",  wflat, 2848, 2879);
    $readmemh("conv2_weight_90.txt",  wflat, 2880, 2911);
    $readmemh("conv2_weight_91.txt",  wflat, 2912, 2943);
    $readmemh("conv2_weight_92.txt",  wflat, 2944, 2975);
    $readmemh("conv2_weight_93.txt",  wflat, 2976, 3007);
    $readmemh("conv2_weight_94.txt",  wflat, 3008, 3039);
    $readmemh("conv2_weight_95.txt",  wflat, 3040, 3071);
    $readmemh("conv2_weight_96.txt",  wflat, 3072, 3103);
    $readmemh("conv2_weight_97.txt",  wflat, 3104, 3135);
    $readmemh("conv2_weight_98.txt",  wflat, 3136, 3167);
    $readmemh("conv2_weight_99.txt",  wflat, 3168, 3199);
    $readmemh("conv2_weight_100.txt", wflat, 3200, 3231);
    $readmemh("conv2_weight_101.txt", wflat, 3232, 3263);
    $readmemh("conv2_weight_102.txt", wflat, 3264, 3295);
    $readmemh("conv2_weight_103.txt", wflat, 3296, 3327);
    $readmemh("conv2_weight_104.txt", wflat, 3328, 3359);
    $readmemh("conv2_weight_105.txt", wflat, 3360, 3391);
    $readmemh("conv2_weight_106.txt", wflat, 3392, 3423);
    $readmemh("conv2_weight_107.txt", wflat, 3424, 3455);
    $readmemh("conv2_weight_108.txt", wflat, 3456, 3487);
    $readmemh("conv2_weight_109.txt", wflat, 3488, 3519);
    $readmemh("conv2_weight_110.txt", wflat, 3520, 3551);
    $readmemh("conv2_weight_111.txt", wflat, 3552, 3583);
    $readmemh("conv2_weight_112.txt", wflat, 3584, 3615);
    $readmemh("conv2_weight_113.txt", wflat, 3616, 3647);
    $readmemh("conv2_weight_114.txt", wflat, 3648, 3679);
    $readmemh("conv2_weight_115.txt", wflat, 3680, 3711);
    $readmemh("conv2_weight_116.txt", wflat, 3712, 3743);
    $readmemh("conv2_weight_117.txt", wflat, 3744, 3775);
    $readmemh("conv2_weight_118.txt", wflat, 3776, 3807);
    $readmemh("conv2_weight_119.txt", wflat, 3808, 3839);
    $readmemh("conv2_weight_120.txt", wflat, 3840, 3871);
    $readmemh("conv2_weight_121.txt", wflat, 3872, 3903);
    $readmemh("conv2_weight_122.txt", wflat, 3904, 3935);
    $readmemh("conv2_weight_123.txt", wflat, 3936, 3967);
    $readmemh("conv2_weight_124.txt", wflat, 3968, 3999);
    $readmemh("conv2_weight_125.txt", wflat, 4000, 4031);
    $readmemh("conv2_weight_126.txt", wflat, 4032, 4063);
    $readmemh("conv2_weight_127.txt", wflat, 4064, 4095);
    $readmemh("conv2_weight_128.txt", wflat, 4096, 4127);
    $readmemh("conv2_weight_129.txt", wflat, 4128, 4159);
    $readmemh("conv2_weight_130.txt", wflat, 4160, 4191);
    $readmemh("conv2_weight_131.txt", wflat, 4192, 4223);
    $readmemh("conv2_weight_132.txt", wflat, 4224, 4255);
    $readmemh("conv2_weight_133.txt", wflat, 4256, 4287);
    $readmemh("conv2_weight_134.txt", wflat, 4288, 4319);
    $readmemh("conv2_weight_135.txt", wflat, 4320, 4351);
    $readmemh("conv2_weight_136.txt", wflat, 4352, 4383);
    $readmemh("conv2_weight_137.txt", wflat, 4384, 4415);
    $readmemh("conv2_weight_138.txt", wflat, 4416, 4447);
    $readmemh("conv2_weight_139.txt", wflat, 4448, 4479);
    $readmemh("conv2_weight_140.txt", wflat, 4480, 4511);
    $readmemh("conv2_weight_141.txt", wflat, 4512, 4543);
    $readmemh("conv2_weight_142.txt", wflat, 4544, 4575);
    $readmemh("conv2_weight_143.txt", wflat, 4576, 4607);
    $readmemh("conv2_bias.txt", bias);
end

localparam S_IDLE  = 3'd0;
localparam S_ADDR  = 3'd1;
localparam S_FETCH = 3'd2;
localparam S_MAC   = 3'd3;
localparam S_ICNXT = 3'd4;
localparam S_WRITE = 3'd5;
localparam S_OCNXT = 3'd6;
localparam S_NEXT  = 3'd7;

reg [2:0] state;
reg [4:0] oc;
reg [3:0] or_;
reg [3:0] oc_col;
reg [3:0] ic;
reg [3:0] k;
reg signed [31:0] acc;

wire signed [4:0] in_r = $signed({1'b0, or_})    + $signed(k / 3) - 1;
wire signed [4:0] in_c = $signed({1'b0, oc_col}) + $signed(k % 3) - 1;
wire is_pad = (in_r < 0)||(in_r >= IN_H)||(in_c < 0)||(in_c >= IN_W);

wire [12:0] widx = (ic * 9 + k) * 32 + oc;

function [7:0] relu_clamp;
    input signed [31:0] v;
    begin
        if (v <= 0)       relu_clamp = 8'd0;
        else if (v > 255) relu_clamp = 8'd255;
        else              relu_clamp = v[7:0];
    end
endfunction

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state<=S_IDLE; done<=0; obram_we<=0;
        oc<=0; or_<=0; oc_col<=0; ic<=0; k<=0; acc<=0;
        ibram_addr<=0; obram_addr<=0; obram_wdata<=0;
    end else begin
        obram_we<=0; done<=0;
        case (state)
            S_IDLE: begin
                if (start) begin
                    oc<=0; or_<=0; oc_col<=0; ic<=0; k<=0;
                    acc <= {{16{bias[0][15]}}, bias[0]};
                    state <= S_ADDR;
                end
            end
            S_ADDR: begin
                if (is_pad) state <= S_MAC;
                else begin
                    ibram_addr <= ic * IN_H * IN_W + in_r[3:0] * IN_W + in_c[3:0];
                    state <= S_FETCH;
                end
            end
            S_FETCH: state <= S_MAC;
            S_MAC: begin
                acc <= acc + $signed({1'b0, (is_pad ? 8'd0 : ibram_rdata)})
                           * $signed(wflat[widx]);
                if (k == 8) begin k<=0; state<=S_ICNXT; end
                else        begin k<=k+1; state<=S_ADDR; end
            end
            S_ICNXT: begin
                if (ic == IN_CH-1) begin ic<=0; state<=S_WRITE; end
                else begin ic<=ic+1; k<=0; state<=S_ADDR; end
            end
            S_WRITE: begin
                obram_wdata <= relu_clamp(acc >>> 7);
                obram_addr  <= oc * OUT_H * OUT_W + or_ * OUT_W + oc_col;
                obram_we<=1; state<=S_OCNXT;
            end
            S_OCNXT: begin
                if (oc == N_OCH-1) begin oc<=0; state<=S_NEXT; end
                else begin
                    oc<=oc+1;
                    acc <= {{16{bias[oc+1][15]}}, bias[oc+1]};
                    ic<=0; k<=0; state<=S_ADDR;
                end
            end
            S_NEXT: begin
                if (oc_col == OUT_W-1) begin
                    oc_col<=0;
                    if (or_ == OUT_H-1) begin or_<=0; done<=1; state<=S_IDLE; end
                    else begin
                        or_<=or_+1;
                        acc <= {{16{bias[0][15]}}, bias[0]};
                        ic<=0; k<=0; state<=S_ADDR;
                    end
                end else begin
                    oc_col<=oc_col+1;
                    acc <= {{16{bias[0][15]}}, bias[0]};
                    ic<=0; k<=0; state<=S_ADDR;
                end
            end
        endcase
    end
end

endmodule