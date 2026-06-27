`timescale 1ns / 1ps
// ============================================================
// conv1.v  - Conv Layer 1
// 8ch → 16ch, 3×3, padding=same
// 입력 : BRAM (24×24×8)  출력 : BRAM (24×24×16, ReLU)
//
// weight 파일: conv1_weight_N.txt (N=0~71)
//   N = in_ch*9 + kernel_pos
//   파일 내 16값 = out_ch 0~15
//
// [수정] 2D 배열 → 1D 플래트닝
//   wfile_flat[N*16 + oc] = weight for file N, out_ch oc
//   총 72×16 = 1152값
// ============================================================

module conv1 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,

    output reg  [12:0] ibram_addr,
    input  wire [7:0]  ibram_rdata,

    output reg  [13:0] obram_addr,   // 24×24×16=9216 → 14-bit
    output reg  [7:0]  obram_wdata,
    output reg         obram_we,

    output reg         done
);

localparam IN_H  = 24;
localparam IN_W  = 24;
localparam IN_CH = 8;
localparam OUT_H = 24;
localparam OUT_W = 24;
localparam N_OCH = 16;

// ── Weight 1D: [N*16 + oc],  N = ic*9+k ─────────────────────
// 72파일 × 16값 = 1152
reg signed [7:0]  wflat [0:1151];
reg signed [15:0] bias  [0:15];

initial begin
    $readmemh("conv1_weight_0.txt",  wflat,   0,  15);
    $readmemh("conv1_weight_1.txt",  wflat,  16,  31);
    $readmemh("conv1_weight_2.txt",  wflat,  32,  47);
    $readmemh("conv1_weight_3.txt",  wflat,  48,  63);
    $readmemh("conv1_weight_4.txt",  wflat,  64,  79);
    $readmemh("conv1_weight_5.txt",  wflat,  80,  95);
    $readmemh("conv1_weight_6.txt",  wflat,  96, 111);
    $readmemh("conv1_weight_7.txt",  wflat, 112, 127);
    $readmemh("conv1_weight_8.txt",  wflat, 128, 143);
    $readmemh("conv1_weight_9.txt",  wflat, 144, 159);
    $readmemh("conv1_weight_10.txt", wflat, 160, 175);
    $readmemh("conv1_weight_11.txt", wflat, 176, 191);
    $readmemh("conv1_weight_12.txt", wflat, 192, 207);
    $readmemh("conv1_weight_13.txt", wflat, 208, 223);
    $readmemh("conv1_weight_14.txt", wflat, 224, 239);
    $readmemh("conv1_weight_15.txt", wflat, 240, 255);
    $readmemh("conv1_weight_16.txt", wflat, 256, 271);
    $readmemh("conv1_weight_17.txt", wflat, 272, 287);
    $readmemh("conv1_weight_18.txt", wflat, 288, 303);
    $readmemh("conv1_weight_19.txt", wflat, 304, 319);
    $readmemh("conv1_weight_20.txt", wflat, 320, 335);
    $readmemh("conv1_weight_21.txt", wflat, 336, 351);
    $readmemh("conv1_weight_22.txt", wflat, 352, 367);
    $readmemh("conv1_weight_23.txt", wflat, 368, 383);
    $readmemh("conv1_weight_24.txt", wflat, 384, 399);
    $readmemh("conv1_weight_25.txt", wflat, 400, 415);
    $readmemh("conv1_weight_26.txt", wflat, 416, 431);
    $readmemh("conv1_weight_27.txt", wflat, 432, 447);
    $readmemh("conv1_weight_28.txt", wflat, 448, 463);
    $readmemh("conv1_weight_29.txt", wflat, 464, 479);
    $readmemh("conv1_weight_30.txt", wflat, 480, 495);
    $readmemh("conv1_weight_31.txt", wflat, 496, 511);
    $readmemh("conv1_weight_32.txt", wflat, 512, 527);
    $readmemh("conv1_weight_33.txt", wflat, 528, 543);
    $readmemh("conv1_weight_34.txt", wflat, 544, 559);
    $readmemh("conv1_weight_35.txt", wflat, 560, 575);
    $readmemh("conv1_weight_36.txt", wflat, 576, 591);
    $readmemh("conv1_weight_37.txt", wflat, 592, 607);
    $readmemh("conv1_weight_38.txt", wflat, 608, 623);
    $readmemh("conv1_weight_39.txt", wflat, 624, 639);
    $readmemh("conv1_weight_40.txt", wflat, 640, 655);
    $readmemh("conv1_weight_41.txt", wflat, 656, 671);
    $readmemh("conv1_weight_42.txt", wflat, 672, 687);
    $readmemh("conv1_weight_43.txt", wflat, 688, 703);
    $readmemh("conv1_weight_44.txt", wflat, 704, 719);
    $readmemh("conv1_weight_45.txt", wflat, 720, 735);
    $readmemh("conv1_weight_46.txt", wflat, 736, 751);
    $readmemh("conv1_weight_47.txt", wflat, 752, 767);
    $readmemh("conv1_weight_48.txt", wflat, 768, 783);
    $readmemh("conv1_weight_49.txt", wflat, 784, 799);
    $readmemh("conv1_weight_50.txt", wflat, 800, 815);
    $readmemh("conv1_weight_51.txt", wflat, 816, 831);
    $readmemh("conv1_weight_52.txt", wflat, 832, 847);
    $readmemh("conv1_weight_53.txt", wflat, 848, 863);
    $readmemh("conv1_weight_54.txt", wflat, 864, 879);
    $readmemh("conv1_weight_55.txt", wflat, 880, 895);
    $readmemh("conv1_weight_56.txt", wflat, 896, 911);
    $readmemh("conv1_weight_57.txt", wflat, 912, 927);
    $readmemh("conv1_weight_58.txt", wflat, 928, 943);
    $readmemh("conv1_weight_59.txt", wflat, 944, 959);
    $readmemh("conv1_weight_60.txt", wflat, 960, 975);
    $readmemh("conv1_weight_61.txt", wflat, 976, 991);
    $readmemh("conv1_weight_62.txt", wflat, 992,1007);
    $readmemh("conv1_weight_63.txt", wflat,1008,1023);
    $readmemh("conv1_weight_64.txt", wflat,1024,1039);
    $readmemh("conv1_weight_65.txt", wflat,1040,1055);
    $readmemh("conv1_weight_66.txt", wflat,1056,1071);
    $readmemh("conv1_weight_67.txt", wflat,1072,1087);
    $readmemh("conv1_weight_68.txt", wflat,1088,1103);
    $readmemh("conv1_weight_69.txt", wflat,1104,1119);
    $readmemh("conv1_weight_70.txt", wflat,1120,1135);
    $readmemh("conv1_weight_71.txt", wflat,1136,1151);
    $readmemh("conv1_bias.txt", bias);
end

// ── FSM ──────────────────────────────────────────────────────
localparam S_IDLE  = 3'd0;
localparam S_ADDR  = 3'd1;
localparam S_FETCH = 3'd2;
localparam S_MAC   = 3'd3;
localparam S_ICNXT = 3'd4;
localparam S_WRITE = 3'd5;
localparam S_OCNXT = 3'd6;
localparam S_NEXT  = 3'd7;

reg [2:0] state;
reg [3:0] oc;
reg [4:0] or_;
reg [4:0] oc_col;
reg [2:0] ic;
reg [3:0] k;
reg signed [31:0] acc;

wire signed [5:0] in_r = $signed({1'b0, or_})    + $signed(k / 3) - 1;
wire signed [5:0] in_c = $signed({1'b0, oc_col}) + $signed(k % 3) - 1;
wire is_pad = (in_r < 0)||(in_r >= IN_H)||(in_c < 0)||(in_c >= IN_W);

// weight 접근: N=ic*9+k, wflat[N*16 + oc]
wire [10:0] widx = (ic * 9 + k) * 16 + oc;

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
                    ibram_addr <= ic * IN_H * IN_W + in_r[4:0] * IN_W + in_c[4:0];
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