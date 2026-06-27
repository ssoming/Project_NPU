`timescale 1ns / 1ps
// ============================================================
// conv0.v  - Conv Layer 0
// 1ch → 8ch, 3×3, padding=same
// 입력 : BRAM (48×48×1)  출력 : BRAM (48×48×8, ReLU)
//
// [수정] $readmemh 2D 배열 오류 수정
//   weight[oc][k] → weight_flat[oc*9 + k] (1D 플래트닝)
//   각 파일: conv0_weight_N.txt (N=oc, 9줄) → weight_flat[N*9 ~ N*9+8]
// ============================================================

module conv0 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,

    output reg  [11:0] ibram_addr,
    input  wire [7:0]  ibram_rdata,

    output reg  [14:0] obram_addr,
    output reg  [7:0]  obram_wdata,
    output reg         obram_we,

    output reg         done
);

localparam IN_H  = 48;
localparam IN_W  = 48;
localparam OUT_H = 48;
localparam OUT_W = 48;
localparam N_OCH = 8;

// ── Weight: 1D 플래트닝 [oc*9 + k] ──────────────────────────
// 8ch × 9kernel = 72값
// conv0_weight_N.txt (N=0~7): 9줄짜리 파일 → weight_flat[N*9 ~ N*9+8]
reg signed [7:0]  weight_flat [0:71];   // [oc*9 + k]
reg signed [15:0] bias        [0:7];

initial begin
    $readmemh("conv0_weight_0.txt", weight_flat,  0,  8);
    $readmemh("conv0_weight_1.txt", weight_flat,  9, 17);
    $readmemh("conv0_weight_2.txt", weight_flat, 18, 26);
    $readmemh("conv0_weight_3.txt", weight_flat, 27, 35);
    $readmemh("conv0_weight_4.txt", weight_flat, 36, 44);
    $readmemh("conv0_weight_5.txt", weight_flat, 45, 53);
    $readmemh("conv0_weight_6.txt", weight_flat, 54, 62);
    $readmemh("conv0_weight_7.txt", weight_flat, 63, 71);
    $readmemh("conv0_bias.txt",     bias);
end

// ── FSM ──────────────────────────────────────────────────────
localparam S_IDLE  = 3'd0;
localparam S_ADDR  = 3'd1;
localparam S_FETCH = 3'd2;
localparam S_MAC   = 3'd3;
localparam S_WRITE = 3'd4;
localparam S_NEXT  = 3'd5;
localparam S_DONE  = 3'd6;

reg [2:0] state;
reg [2:0] oc;
reg [5:0] or_;
reg [5:0] oc_col;
reg [3:0] k;
reg signed [31:0] acc;

// padding=same: in_r = or_+kr-1, in_c = oc_col+kc-1
wire signed [6:0] in_r = $signed({1'b0, or_})    + $signed(k / 3) - 1;
wire signed [6:0] in_c = $signed({1'b0, oc_col}) + $signed(k % 3) - 1;
wire is_pad = (in_r < 0) || (in_r >= IN_H) || (in_c < 0) || (in_c >= IN_W);

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
        oc<=0; or_<=0; oc_col<=0; k<=0; acc<=0;
        ibram_addr<=0; obram_addr<=0; obram_wdata<=0;
    end else begin
        obram_we <= 0;
        done     <= 0;
        case (state)
            S_IDLE: begin
                if (start) begin
                    oc<=0; or_<=0; oc_col<=0; k<=0;
                    acc <= {{16{bias[0][15]}}, bias[0]};
                    state <= S_ADDR;
                end
            end
            S_ADDR: begin
                if (is_pad) state <= S_MAC;
                else begin
                    ibram_addr <= in_r[5:0] * IN_W + in_c[5:0];
                    state <= S_FETCH;
                end
            end
            S_FETCH: state <= S_MAC;
            S_MAC: begin
                acc <= acc + $signed({1'b0, (is_pad ? 8'd0 : ibram_rdata)})
                           * $signed(weight_flat[oc * 9 + k]);
                if (k == 8) begin k<=0; state<=S_WRITE; end
                else        begin k<=k+1; state<=S_ADDR; end
            end
            S_WRITE: begin
                obram_wdata <= relu_clamp(acc >>> 7);
                obram_addr  <= oc * OUT_H * OUT_W + or_ * OUT_W + oc_col;
                obram_we<=1; state<=S_NEXT;
            end
            S_NEXT: begin
                if (oc_col == OUT_W-1) begin
                    oc_col<=0;
                    if (or_ == OUT_H-1) begin
                        or_<=0;
                        if (oc == N_OCH-1) state<=S_DONE;
                        else begin
                            oc<=oc+1;
                            acc <= {{16{bias[oc+1][15]}}, bias[oc+1]};
                            k<=0; state<=S_ADDR;
                        end
                    end else begin
                        or_<=or_+1;
                        acc <= {{16{bias[oc][15]}}, bias[oc]};
                        k<=0; state<=S_ADDR;
                    end
                end else begin
                    oc_col<=oc_col+1;
                    acc <= {{16{bias[oc][15]}}, bias[oc]};
                    k<=0; state<=S_ADDR;
                end
            end
            S_DONE: begin done<=1; state<=S_IDLE; end
        endcase
    end
end

endmodule