`timescale 1ns / 1ps
// ============================================================
// maxpool.v
// 2×2 MaxPooling, stride=2 (범용 - 채널 수/크기 파라미터화)
//
// 입력  : BRAM (IN_H × IN_W × N_CH, 8-bit unsigned)
// 출력  : BRAM (IN_H/2 × IN_W/2 × N_CH, 8-bit unsigned)
//
// 주소 배치 (입력/출력 모두 channel-first)
//   입력 addr = ch * IN_H * IN_W + row * IN_W + col
//   출력 addr = ch * OH  * OW   + or_ * OW   + oc_col
//
// FSM : IDLE → FETCH(4사이클) → COMP → WRITE → NEXT
// ============================================================

module maxpool #(
    parameter IN_H  = 46,
    parameter IN_W  = 46,
    parameter N_CH  = 8,
    // 자동 계산
    parameter OH    = IN_H / 2,
    parameter OW    = IN_W / 2,
    parameter IADDR = $clog2(IN_H * IN_W * N_CH),
    parameter OADDR = $clog2(OH   * OW   * N_CH)
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              start,

    output reg  [IADDR-1:0] ibram_addr,
    input  wire [7:0]        ibram_rdata,

    output reg  [OADDR-1:0] obram_addr,
    output reg  [7:0]        obram_wdata,
    output reg               obram_we,

    output reg               done
);

// ── FSM ──────────────────────────────────────────────────────
localparam S_IDLE  = 3'd0;
localparam S_FETCH = 3'd1;
localparam S_COMP  = 3'd2;
localparam S_WRITE = 3'd3;
localparam S_NEXT  = 3'd4;
localparam S_DONE  = 3'd5;

reg [2:0] state;

// ── 카운터 ───────────────────────────────────────────────────
reg [$clog2(N_CH)-1:0] ch;
reg [$clog2(OH)-1:0]   or_;
reg [$clog2(OW)-1:0]   oc_col;
reg [2:0]              cnt;    // 0~4

// ── 2×2 픽셀 버퍼 ────────────────────────────────────────────
reg [7:0] px [0:3];
reg [7:0] max_val;

// ── 2×2 윈도우 픽셀 BRAM 주소 ────────────────────────────────
// pos 0: (2*or_,   2*oc_col)
// pos 1: (2*or_,   2*oc_col+1)
// pos 2: (2*or_+1, 2*oc_col)
// pos 3: (2*or_+1, 2*oc_col+1)
function [IADDR-1:0] paddr;
    input [$clog2(N_CH)-1:0] c;
    input [$clog2(OH)-1:0]   r;
    input [$clog2(OW)-1:0]   col;
    input [1:0]               pos;
    reg [$clog2(IN_H)-1:0] row_off;
    reg [$clog2(IN_W)-1:0] col_off;
    begin
        row_off = {r, pos[1]};   // r*2 + pos[1]: concat avoids shift overflow
        col_off = {col, pos[0]}; // col*2 + pos[0]
        paddr   = c * IN_H * IN_W + row_off * IN_W + col_off;
    end
endfunction

// ── 메인 FSM ─────────────────────────────────────────────────
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state       <= S_IDLE;
        done        <= 1'b0;
        obram_we    <= 1'b0;
        ch          <= 0;
        or_         <= 0;
        oc_col      <= 0;
        cnt         <= 3'd0;
        max_val     <= 8'd0;
        ibram_addr  <= 0;
        obram_addr  <= 0;
        obram_wdata <= 8'd0;
    end else begin
        obram_we <= 1'b0;
        done     <= 1'b0;

        case (state)

            S_IDLE: begin
                if (start) begin
                    ch     <= 0;
                    or_    <= 0;
                    oc_col <= 0;
                    cnt    <= 3'd0;
                    ibram_addr <= paddr(0, 0, 0, 2'b00);
                    state  <= S_FETCH;
                end
            end

            // cnt=0: 주소 세팅 완료, 대기
            // cnt=1: px[0]←rdata, 주소=pos1
            // cnt=2: px[1]←rdata, 주소=pos2
            // cnt=3: px[2]←rdata, 주소=pos3
            // cnt=4: px[3]←rdata → COMP
            S_FETCH: begin
                cnt <= cnt + 1;
                if (cnt >= 1)
                    px[cnt - 1] <= ibram_rdata;
                case (cnt)
                    3'd1: ibram_addr <= paddr(ch, or_, oc_col, 2'b01);
                    3'd2: ibram_addr <= paddr(ch, or_, oc_col, 2'b10);
                    3'd3: ibram_addr <= paddr(ch, or_, oc_col, 2'b11);
                    default: ;
                endcase
                if (cnt == 4) begin
                    cnt   <= 3'd0;
                    state <= S_COMP;
                end
            end

            S_COMP: begin
                // 4값 max
                begin : max4
                    reg [7:0] m0, m1;
                    m0 = (px[0] > px[1]) ? px[0] : px[1];
                    m1 = (px[2] > px[3]) ? px[2] : px[3];
                    max_val <= (m0 > m1) ? m0 : m1;
                end
                state <= S_WRITE;
            end

            S_WRITE: begin
                obram_wdata <= max_val;
                obram_addr  <= ch * OH * OW + or_ * OW + oc_col;
                obram_we    <= 1'b1;
                state       <= S_NEXT;
            end

            S_NEXT: begin
                if (oc_col == OW - 1) begin
                    oc_col <= 0;
                    if (or_ == OH - 1) begin
                        or_ <= 0;
                        if (ch == N_CH - 1) begin
                            state <= S_DONE;
                        end else begin
                            ch         <= ch + 1;
                            ibram_addr <= paddr(ch + 1, 0, 0, 2'b00);
                            cnt        <= 3'd0;
                            state      <= S_FETCH;
                        end
                    end else begin
                        or_        <= or_ + 1;
                        ibram_addr <= paddr(ch, or_ + 1, 0, 2'b00);
                        cnt        <= 3'd0;
                        state      <= S_FETCH;
                    end
                end else begin
                    oc_col     <= oc_col + 1;
                    ibram_addr <= paddr(ch, or_, oc_col + 1, 2'b00);
                    cnt        <= 3'd0;
                    state      <= S_FETCH;
                end
            end

            S_DONE: begin
                done  <= 1'b1;
                state <= S_IDLE;
            end

        endcase
    end
end

endmodule