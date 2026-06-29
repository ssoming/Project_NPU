`timescale 1ns / 1ps

// ============================================================
// BRAM 추론 조건 (Vivado Simple Dual Port):
//   읽기 포트: 별도 always 블록 (posedge clk에서 rdata <= mem[addr])
//   쓰기 포트: 별도 always 블록 (posedge clk에서 mem[addr] <= wdata)
//   → FSM always 블록 내부에서 직접 mem[addr] <= data 하면 BRAM 추론 실패!
//   수정: fm1/pool1/fm2/pool2/fm3/pool3 각각 we/waddr/wdata 신호 분리
// ============================================================

module cnn_core_fsm_v2 #(
    parameter BN_SHIFT = 16
)(
    input  wire clk,
    input  wire reset_p,
    input  wire start,
    output reg  done,
    output reg  busy,
    output reg  [3:0] class_idx,
    input  wire        img_we,
    input  wire [11:0] img_addr,
    input  wire signed [15:0] img_wdata
);

    // ============================================================
    // States
    // ============================================================
    localparam [5:0]
        S_IDLE        = 6'd0,
        S_CONV1_INIT  = 6'd1,
        S_CONV1_ADDR  = 6'd2,
        S_CONV1_READ  = 6'd3,
        S_CONV1_MAC   = 6'd4,
        S_CONV1_SAVE  = 6'd5,

        S_POOL1_ADDR  = 6'd6,
        S_POOL1_READ  = 6'd7,
        S_POOL1_CMP   = 6'd8,
        S_POOL1_SAVE  = 6'd9,

        S_CONV2_INIT  = 6'd10,
        S_CONV2_ADDR  = 6'd11,
        S_CONV2_READ  = 6'd12,
        S_CONV2_MAC   = 6'd13,
        S_CONV2_SAVE  = 6'd14,

        S_POOL2_ADDR  = 6'd15,
        S_POOL2_READ  = 6'd16,
        S_POOL2_CMP   = 6'd17,
        S_POOL2_SAVE  = 6'd18,

        S_CONV3_INIT  = 6'd19,
        S_CONV3_ADDR  = 6'd20,
        S_CONV3_READ  = 6'd21,
        S_CONV3_MAC   = 6'd22,
        S_CONV3_SAVE  = 6'd23,

        S_POOL3_ADDR  = 6'd24,
        S_POOL3_READ  = 6'd25,
        S_POOL3_CMP   = 6'd26,
        S_POOL3_SAVE  = 6'd27,

        S_D1_INIT     = 6'd28,
        S_D1_ADDR     = 6'd29,
        S_D1_READ     = 6'd30,
        S_D1_MAC      = 6'd31,
        S_D1_SAVE     = 6'd32,

        S_D2_INIT     = 6'd33,
        S_D2_ADDR     = 6'd34,
        S_D2_READ     = 6'd35,
        S_D2_MAC      = 6'd36,
        S_D2_SAVE     = 6'd37,

        S_ARGMAX_INIT = 6'd38,
        S_ARGMAX_SCAN = 6'd39,
        S_DONE        = 6'd40;

    reg [5:0] state;

    // ============================================================
    // BRAM: 가중치 (읽기 전용)
    // ============================================================
    (* ram_style="block" *) reg signed [7:0]  conv1_w [0:71];
    (* ram_style="block" *) reg signed [63:0] conv1_b [0:7];
                            reg signed [31:0] bn1_mul  [0:7];
                            reg signed [31:0] bn1_add  [0:7];

    (* ram_style="block" *) reg signed [7:0]  conv2_w [0:1151];
    (* ram_style="block" *) reg signed [63:0] conv2_b [0:15];
                            reg signed [31:0] bn2_mul  [0:15];
                            reg signed [31:0] bn2_add  [0:15];

    (* ram_style="block" *) reg signed [7:0]  conv3_w [0:4607];
    (* ram_style="block" *) reg signed [63:0] conv3_b [0:31];
                            reg signed [31:0] bn3_mul  [0:31];
                            reg signed [31:0] bn3_add  [0:31];

    (* ram_style="block" *) reg signed [7:0]  dense1_w [0:73727];
    (* ram_style="block" *) reg signed [63:0] dense1_b [0:63];
    (* ram_style="block" *) reg signed [7:0]  dense2_w [0:575];
                            reg signed [63:0] dense2_b [0:8];

    // ============================================================
    // BRAM: feature map 배열 선언
    // ============================================================
    (* ram_style="block" *) reg signed [31:0] img_mem [0:2303];   // 48*48
    (* ram_style="block" *) reg signed [31:0] fm1     [0:18431];  // 48*48*8
    (* ram_style="block" *) reg signed [31:0] pool1   [0:4607];   // 24*24*8
    (* ram_style="block" *) reg signed [31:0] fm2     [0:9215];   // 24*24*16
    (* ram_style="block" *) reg signed [31:0] pool2   [0:2303];   // 12*12*16
    (* ram_style="block" *) reg signed [31:0] fm3     [0:4607];   // 12*12*32
    (* ram_style="block" *) reg signed [31:0] pool3   [0:1151];   // 6*6*32

                            reg signed [63:0] dense1_out [0:63];
                            reg signed [63:0] dense2_out [0:8];

    // ============================================================
    // Feature map 쓰기 포트 신호 (FSM에서 제어, 별도 always 블록에서 write)
    // ============================================================
    reg        fm1_we;   reg [14:0] fm1_waddr;  reg signed [31:0] fm1_wdata;
    reg        pool1_we; reg [12:0] pool1_waddr; reg signed [31:0] pool1_wdata;
    reg        fm2_we;   reg [13:0] fm2_waddr;  reg signed [31:0] fm2_wdata;
    reg        pool2_we; reg [11:0] pool2_waddr; reg signed [31:0] pool2_wdata;
    reg        fm3_we;   reg [12:0] fm3_waddr;  reg signed [31:0] fm3_wdata;
    reg        pool3_we; reg [10:0] pool3_waddr; reg signed [31:0] pool3_wdata;

    // ============================================================
    // BRAM 쓰기 포트 (FSM 블록과 분리된 별도 always 블록)
    // Vivado Simple Dual Port BRAM 추론 조건 충족
    // ============================================================
    always @(posedge clk) begin
        if (img_we && !busy)
            img_mem[img_addr] <= $signed({1'b0, img_wdata});
    end

    always @(posedge clk) begin
        if (fm1_we)   fm1[fm1_waddr]     <= fm1_wdata;
    end
    always @(posedge clk) begin
        if (pool1_we) pool1[pool1_waddr] <= pool1_wdata;
    end
    always @(posedge clk) begin
        if (fm2_we)   fm2[fm2_waddr]     <= fm2_wdata;
    end
    always @(posedge clk) begin
        if (pool2_we) pool2[pool2_waddr] <= pool2_wdata;
    end
    always @(posedge clk) begin
        if (fm3_we)   fm3[fm3_waddr]     <= fm3_wdata;
    end
    always @(posedge clk) begin
        if (pool3_we) pool3[pool3_waddr] <= pool3_wdata;
    end

    // ============================================================
    // 초기화 (시뮬레이션용)
    // ============================================================
    initial begin
        $readmemh("conv1_w.mem",  conv1_w);  $readmemh("conv1_b.mem",  conv1_b);
        $readmemh("bn1_mul.mem",  bn1_mul);  $readmemh("bn1_add.mem",  bn1_add);
        $readmemh("conv2_w.mem",  conv2_w);  $readmemh("conv2_b.mem",  conv2_b);
        $readmemh("bn2_mul.mem",  bn2_mul);  $readmemh("bn2_add.mem",  bn2_add);
        $readmemh("conv3_w.mem",  conv3_w);  $readmemh("conv3_b.mem",  conv3_b);
        $readmemh("bn3_mul.mem",  bn3_mul);  $readmemh("bn3_add.mem",  bn3_add);
        $readmemh("dense1_w.mem", dense1_w); $readmemh("dense1_b.mem", dense1_b);
        $readmemh("dense2_w.mem", dense2_w); $readmemh("dense2_b.mem", dense2_b);
    end

    // ============================================================
    // BRAM 동기 읽기 포트
    // ============================================================
    reg  [11:0]        img_raddr;
    reg  signed [31:0] img_rdata;
    always @(posedge clk) img_rdata <= img_mem[img_raddr];

    reg  [6:0]        c1w_addr;
    reg  signed [7:0] c1w_rdata;
    always @(posedge clk) c1w_rdata <= conv1_w[c1w_addr];

    reg  [10:0]       c2w_addr;
    reg  signed [7:0] c2w_rdata;
    always @(posedge clk) c2w_rdata <= conv2_w[c2w_addr];

    reg  [12:0]       c3w_addr;
    reg  signed [7:0] c3w_rdata;
    always @(posedge clk) c3w_rdata <= conv3_w[c3w_addr];

    reg  [12:0]        p1r_addr;
    reg  signed [31:0] p1r_rdata;
    always @(posedge clk) p1r_rdata <= pool1[p1r_addr];

    reg  [11:0]        p2r_addr;
    reg  signed [31:0] p2r_rdata;
    always @(posedge clk) p2r_rdata <= pool2[p2r_addr];

    reg  [10:0]        p3r_addr;
    reg  signed [31:0] p3r_rdata;
    always @(posedge clk) p3r_rdata <= pool3[p3r_addr];

    reg  [14:0]        fm1r_addr;
    reg  signed [31:0] fm1r_rdata;
    always @(posedge clk) fm1r_rdata <= fm1[fm1r_addr];

    reg  [13:0]        fm2r_addr;
    reg  signed [31:0] fm2r_rdata;
    always @(posedge clk) fm2r_rdata <= fm2[fm2r_addr];

    reg  [12:0]        fm3r_addr;
    reg  signed [31:0] fm3r_rdata;
    always @(posedge clk) fm3r_rdata <= fm3[fm3r_addr];

    reg  [16:0]       d1w_addr;
    reg  signed [7:0] d1w_rdata;
    always @(posedge clk) d1w_rdata <= dense1_w[d1w_addr];

    reg  [9:0]        d2w_addr;
    reg  signed [7:0] d2w_rdata;
    always @(posedge clk) d2w_rdata <= dense2_w[d2w_addr];

    // ============================================================
    // 인덱스 계산 함수
    // ============================================================
    function [14:0] fm_idx_48x8;
        input [5:0] h, w, c;
        begin fm_idx_48x8 = (h*48+w)*8+c; end
    endfunction
    function [12:0] fm_idx_24x8;
        input [4:0] h, w; input [2:0] c;
        begin fm_idx_24x8 = (h*24+w)*8+c; end
    endfunction
    function [13:0] fm_idx_24x16;
        input [4:0] h, w; input [3:0] c;
        begin fm_idx_24x16 = (h*24+w)*16+c; end
    endfunction
    function [11:0] fm_idx_12x16;
        input [3:0] h, w; input [3:0] c;
        begin fm_idx_12x16 = (h*12+w)*16+c; end
    endfunction
    function [12:0] fm_idx_12x32;
        input [3:0] h, w; input [4:0] c;
        begin fm_idx_12x32 = (h*12+w)*32+c; end
    endfunction
    function [10:0] fm_idx_6x32;
        input [2:0] h, w; input [4:0] c;
        begin fm_idx_6x32 = (h*6+w)*32+c; end
    endfunction

    // ============================================================
    // 카운터
    // ============================================================
    reg [5:0]  oh, ow, oc, ic;
    reg [1:0]  kh, kw;
    reg [5:0]  ph, pw, pc;
    reg [10:0] dense_i;
    reg [6:0]  dense_o;
    reg [3:0]  arg_i;
    reg [1:0]  pool_step;

    reg signed [63:0] sum;
    reg signed [95:0] bn_mult;
    reg signed [31:0] pool_max;
    reg signed [63:0] max_val;

    // ============================================================
    // FSM
    // ============================================================
    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin
            state <= S_IDLE;
            done<=0; busy<=0; class_idx<=0;
            oh<=0; ow<=0; oc<=0; ic<=0;
            kh<=0; kw<=0; ph<=0; pw<=0; pc<=0;
            dense_i<=0; dense_o<=0; arg_i<=0; pool_step<=0;
            sum<=0; pool_max<=0; max_val<=0;
            img_raddr<=0; c1w_addr<=0; c2w_addr<=0; c3w_addr<=0;
            fm1r_addr<=0; fm2r_addr<=0; fm3r_addr<=0;
            p1r_addr<=0; p2r_addr<=0; p3r_addr<=0;
            d1w_addr<=0; d2w_addr<=0;
            // write port 신호 초기화
            fm1_we<=0;   fm1_waddr<=0;   fm1_wdata<=0;
            pool1_we<=0; pool1_waddr<=0; pool1_wdata<=0;
            fm2_we<=0;   fm2_waddr<=0;   fm2_wdata<=0;
            pool2_we<=0; pool2_waddr<=0; pool2_wdata<=0;
            fm3_we<=0;   fm3_waddr<=0;   fm3_wdata<=0;
            pool3_we<=0; pool3_waddr<=0; pool3_wdata<=0;
        end else begin
            // 기본적으로 write-enable 클리어 (pulse 방식)
            fm1_we   <= 0;
            pool1_we <= 0;
            fm2_we   <= 0;
            pool2_we <= 0;
            fm3_we   <= 0;
            pool3_we <= 0;

            case (state)

            // ── IDLE ──────────────────────────────────────────
            S_IDLE: begin
                done <= 0;
                if (start && !busy) begin
                    busy<=1; class_idx<=0;
                    oh<=0; ow<=0; oc<=0; ic<=0;
                    kh<=0; kw<=0; ph<=0; pw<=0; pc<=0;
                    dense_i<=0; dense_o<=0; arg_i<=0;
                    state <= S_CONV1_INIT;
                    $display("FSM start");
                end
            end

            // ── CONV1 (48x48x1 → 48x48x8) ────────────────────
            S_CONV1_INIT: begin
                sum  <= conv1_b[oc];
                kh<=0; kw<=0;
                state <= S_CONV1_ADDR;
            end

            S_CONV1_ADDR: begin
                if (($signed({1'b0,oh})+$signed({1'b0,kh})-1 >= 0) &&
                    ($signed({1'b0,oh})+$signed({1'b0,kh})-1 < 48) &&
                    ($signed({1'b0,ow})+$signed({1'b0,kw})-1 >= 0) &&
                    ($signed({1'b0,ow})+$signed({1'b0,kw})-1 < 48)) begin
                    img_raddr <= ($signed({1'b0,oh})+$signed({1'b0,kh})-1)*48 +
                                 ($signed({1'b0,ow})+$signed({1'b0,kw})-1);
                    c1w_addr  <= (kh*3+kw)*8 + oc;
                    state <= S_CONV1_READ;
                end else begin
                    state <= S_CONV1_MAC;
                end
            end

            S_CONV1_READ: begin
                state <= S_CONV1_MAC;
            end

            S_CONV1_MAC: begin
                sum <= sum + $signed(img_rdata[15:0]) * $signed(c1w_rdata);

                if (kw==2) begin kw<=0;
                    if (kh==2) begin kh<=0; state<=S_CONV1_SAVE; end
                    else begin kh<=kh+1; state<=S_CONV1_ADDR; end
                end else begin kw<=kw+1; state<=S_CONV1_ADDR; end
            end

            S_CONV1_SAVE: begin
                bn_mult = (sum<0 ? 96'd0 : {32'd0,sum[63:0]}) * $signed({1'b0,bn1_mul[oc]});
                // FSM 내에서 직접 쓰는 대신, write 신호 구동
                fm1_we    <= 1;
                fm1_waddr <= fm_idx_48x8(oh,ow,oc);
                fm1_wdata <= (bn_mult>>>BN_SHIFT) + $signed(bn1_add[oc]);

                if (oc==7) begin oc<=0;
                    if (ow==47) begin ow<=0;
                        if (oh==47) begin oh<=0; ph<=0; pw<=0; pc<=0; pool_step<=0;
                            state<=S_POOL1_ADDR; $display("conv1 done");
                        end else begin oh<=oh+1; state<=S_CONV1_INIT; end
                    end else begin ow<=ow+1; state<=S_CONV1_INIT; end
                end else begin oc<=oc+1; state<=S_CONV1_INIT; end
            end

            // ── POOL1 (48x48x8 → 24x24x8) ────────────────────
            S_POOL1_ADDR: begin
                case (pool_step)
                    2'd0: fm1r_addr <= fm_idx_48x8(ph*2,   pw*2,   pc);
                    2'd1: fm1r_addr <= fm_idx_48x8(ph*2,   pw*2+1, pc);
                    2'd2: fm1r_addr <= fm_idx_48x8(ph*2+1, pw*2,   pc);
                    2'd3: fm1r_addr <= fm_idx_48x8(ph*2+1, pw*2+1, pc);
                endcase
                state <= S_POOL1_READ;
            end

            S_POOL1_READ: begin
                state <= S_POOL1_CMP;
            end

            S_POOL1_CMP: begin
                if (pool_step==0)
                    pool_max <= fm1r_rdata;
                else if (fm1r_rdata > pool_max)
                    pool_max <= fm1r_rdata;

                if (pool_step==3) begin
                    pool_step<=0;
                    state<=S_POOL1_SAVE;
                end else begin
                    pool_step<=pool_step+1;
                    state<=S_POOL1_ADDR;
                end
            end

            S_POOL1_SAVE: begin
                pool1_we    <= 1;
                pool1_waddr <= fm_idx_24x8(ph,pw,pc[2:0]);
                pool1_wdata <= pool_max;

                if (pc==7) begin pc<=0;
                    if (pw==23) begin pw<=0;
                        if (ph==23) begin ph<=0;
                            oh<=0; ow<=0; oc<=0; ic<=0; kh<=0; kw<=0;
                            state<=S_CONV2_INIT; $display("pool1 done");
                        end else begin ph<=ph+1; state<=S_POOL1_ADDR; end
                    end else begin pw<=pw+1; state<=S_POOL1_ADDR; end
                end else begin pc<=pc+1; state<=S_POOL1_ADDR; end
            end

            // ── CONV2 (24x24x8 → 24x24x16) ───────────────────
            S_CONV2_INIT: begin
                sum <= conv2_b[oc];
                kh<=0; kw<=0; ic<=0;
                state <= S_CONV2_ADDR;
            end

            S_CONV2_ADDR: begin
                if (($signed({1'b0,oh})+$signed({1'b0,kh})-1 >= 0) &&
                    ($signed({1'b0,oh})+$signed({1'b0,kh})-1 < 24) &&
                    ($signed({1'b0,ow})+$signed({1'b0,kw})-1 >= 0) &&
                    ($signed({1'b0,ow})+$signed({1'b0,kw})-1 < 24)) begin
                    p1r_addr <= fm_idx_24x8(
                        ($signed({1'b0,oh})+$signed({1'b0,kh})-1),
                        ($signed({1'b0,ow})+$signed({1'b0,kw})-1),
                        ic[2:0]);
                    c2w_addr <= ((kh*3+kw)*8+ic)*16+oc;
                    state <= S_CONV2_READ;
                end else begin
                    state <= S_CONV2_MAC;
                end
            end

            S_CONV2_READ: begin
                state <= S_CONV2_MAC;
            end

            S_CONV2_MAC: begin
                sum <= sum + $signed(p1r_rdata) * $signed(c2w_rdata);

                if (ic==7) begin ic<=0;
                    if (kw==2) begin kw<=0;
                        if (kh==2) begin kh<=0; state<=S_CONV2_SAVE; end
                        else begin kh<=kh+1; state<=S_CONV2_ADDR; end
                    end else begin kw<=kw+1; state<=S_CONV2_ADDR; end
                end else begin ic<=ic+1; state<=S_CONV2_ADDR; end
            end

            S_CONV2_SAVE: begin
                bn_mult = (sum<0 ? 96'd0 : {32'd0,sum[63:0]}) * $signed({1'b0,bn2_mul[oc]});
                fm2_we    <= 1;
                fm2_waddr <= fm_idx_24x16(oh,ow,oc[3:0]);
                fm2_wdata <= (bn_mult>>>BN_SHIFT) + $signed(bn2_add[oc]);

                if (oc==15) begin oc<=0;
                    if (ow==23) begin ow<=0;
                        if (oh==23) begin oh<=0; ph<=0; pw<=0; pc<=0; pool_step<=0;
                            state<=S_POOL2_ADDR; $display("conv2 done");
                        end else begin oh<=oh+1; state<=S_CONV2_INIT; end
                    end else begin ow<=ow+1; state<=S_CONV2_INIT; end
                end else begin oc<=oc+1; state<=S_CONV2_INIT; end
            end

            // ── POOL2 (24x24x16 → 12x12x16) ──────────────────
            S_POOL2_ADDR: begin
                case (pool_step)
                    2'd0: fm2r_addr <= fm_idx_24x16(ph*2,   pw*2,   pc[3:0]);
                    2'd1: fm2r_addr <= fm_idx_24x16(ph*2,   pw*2+1, pc[3:0]);
                    2'd2: fm2r_addr <= fm_idx_24x16(ph*2+1, pw*2,   pc[3:0]);
                    2'd3: fm2r_addr <= fm_idx_24x16(ph*2+1, pw*2+1, pc[3:0]);
                endcase
                state <= S_POOL2_READ;
            end
            S_POOL2_READ: begin state <= S_POOL2_CMP; end
            S_POOL2_CMP: begin
                if (pool_step==0) pool_max <= fm2r_rdata;
                else if (fm2r_rdata > pool_max) pool_max <= fm2r_rdata;
                if (pool_step==3) begin pool_step<=0; state<=S_POOL2_SAVE; end
                else begin pool_step<=pool_step+1; state<=S_POOL2_ADDR; end
            end
            S_POOL2_SAVE: begin
                pool2_we    <= 1;
                pool2_waddr <= fm_idx_12x16(ph,pw,pc[3:0]);
                pool2_wdata <= pool_max;

                if (pc==15) begin pc<=0;
                    if (pw==11) begin pw<=0;
                        if (ph==11) begin ph<=0;
                            oh<=0; ow<=0; oc<=0; ic<=0; kh<=0; kw<=0;
                            state<=S_CONV3_INIT; $display("pool2 done");
                        end else begin ph<=ph+1; state<=S_POOL2_ADDR; end
                    end else begin pw<=pw+1; state<=S_POOL2_ADDR; end
                end else begin pc<=pc+1; state<=S_POOL2_ADDR; end
            end

            // ── CONV3 (12x12x16 → 12x12x32) ──────────────────
            S_CONV3_INIT: begin
                sum <= conv3_b[oc];
                kh<=0; kw<=0; ic<=0;
                state <= S_CONV3_ADDR;
            end

            S_CONV3_ADDR: begin
                if (($signed({1'b0,oh})+$signed({1'b0,kh})-1 >= 0) &&
                    ($signed({1'b0,oh})+$signed({1'b0,kh})-1 < 12) &&
                    ($signed({1'b0,ow})+$signed({1'b0,kw})-1 >= 0) &&
                    ($signed({1'b0,ow})+$signed({1'b0,kw})-1 < 12)) begin
                    p2r_addr <= fm_idx_12x16(
                        ($signed({1'b0,oh})+$signed({1'b0,kh})-1),
                        ($signed({1'b0,ow})+$signed({1'b0,kw})-1),
                        ic[3:0]);
                    c3w_addr <= ((kh*3+kw)*16+ic)*32+oc;
                    state <= S_CONV3_READ;
                end else begin
                    state <= S_CONV3_MAC;
                end
            end

            S_CONV3_READ: begin state <= S_CONV3_MAC; end

            S_CONV3_MAC: begin
                sum <= sum + $signed(p2r_rdata) * $signed(c3w_rdata);

                if (ic==15) begin ic<=0;
                    if (kw==2) begin kw<=0;
                        if (kh==2) begin kh<=0; state<=S_CONV3_SAVE; end
                        else begin kh<=kh+1; state<=S_CONV3_ADDR; end
                    end else begin kw<=kw+1; state<=S_CONV3_ADDR; end
                end else begin ic<=ic+1; state<=S_CONV3_ADDR; end
            end

            S_CONV3_SAVE: begin
                bn_mult = (sum<0 ? 96'd0 : {32'd0,sum[63:0]}) * $signed({1'b0,bn3_mul[oc]});
                fm3_we    <= 1;
                fm3_waddr <= fm_idx_12x32(oh,ow,oc[4:0]);
                fm3_wdata <= (bn_mult>>>BN_SHIFT) + $signed(bn3_add[oc]);

                if (oc==31) begin oc<=0;
                    if (ow==11) begin ow<=0;
                        if (oh==11) begin oh<=0; ph<=0; pw<=0; pc<=0; pool_step<=0;
                            state<=S_POOL3_ADDR; $display("conv3 done");
                        end else begin oh<=oh+1; state<=S_CONV3_INIT; end
                    end else begin ow<=ow+1; state<=S_CONV3_INIT; end
                end else begin oc<=oc+1; state<=S_CONV3_INIT; end
            end

            // ── POOL3 (12x12x32 → 6x6x32) ────────────────────
            S_POOL3_ADDR: begin
                case (pool_step)
                    2'd0: fm3r_addr <= fm_idx_12x32(ph*2,   pw*2,   pc[4:0]);
                    2'd1: fm3r_addr <= fm_idx_12x32(ph*2,   pw*2+1, pc[4:0]);
                    2'd2: fm3r_addr <= fm_idx_12x32(ph*2+1, pw*2,   pc[4:0]);
                    2'd3: fm3r_addr <= fm_idx_12x32(ph*2+1, pw*2+1, pc[4:0]);
                endcase
                state <= S_POOL3_READ;
            end
            S_POOL3_READ: begin state <= S_POOL3_CMP; end
            S_POOL3_CMP: begin
                if (pool_step==0) pool_max <= fm3r_rdata;
                else if (fm3r_rdata > pool_max) pool_max <= fm3r_rdata;
                if (pool_step==3) begin pool_step<=0; state<=S_POOL3_SAVE; end
                else begin pool_step<=pool_step+1; state<=S_POOL3_ADDR; end
            end
            S_POOL3_SAVE: begin
                pool3_we    <= 1;
                pool3_waddr <= fm_idx_6x32(ph,pw,pc[4:0]);
                pool3_wdata <= pool_max;

                if (pc==31) begin pc<=0;
                    if (pw==5) begin pw<=0;
                        if (ph==5) begin ph<=0;
                            dense_o<=0; dense_i<=0;
                            state<=S_D1_INIT; $display("pool3 done");
                        end else begin ph<=ph+1; state<=S_POOL3_ADDR; end
                    end else begin pw<=pw+1; state<=S_POOL3_ADDR; end
                end else begin pc<=pc+1; state<=S_POOL3_ADDR; end
            end

            // ── DENSE1 (1152→64, ReLU) ────────────────────────
            S_D1_INIT: begin
                sum <= dense1_b[dense_o];
                dense_i <= 0;
                p3r_addr <= 0;
                d1w_addr <= dense_o;
                state <= S_D1_ADDR;
            end

            S_D1_ADDR: begin
                p3r_addr <= dense_i[10:0];
                d1w_addr <= dense_i*64 + dense_o;
                state <= S_D1_READ;
            end

            S_D1_READ: begin
                state <= S_D1_MAC;
            end

            S_D1_MAC: begin
                sum <= sum + $signed(p3r_rdata) * $signed(d1w_rdata);

                if (dense_i==1151) begin dense_i<=0; state<=S_D1_SAVE; end
                else begin dense_i<=dense_i+1; state<=S_D1_ADDR; end
            end

            S_D1_SAVE: begin
                dense1_out[dense_o] <= (sum<0) ? 64'd0 : sum;
                if (dense_o==63) begin dense_o<=0; dense_i<=0;
                    state<=S_D2_INIT; $display("dense1 done");
                end else begin dense_o<=dense_o+1; state<=S_D1_INIT; end
            end

            // ── DENSE2 (64→9) ─────────────────────────────────
            S_D2_INIT: begin
                sum <= dense2_b[dense_o];
                dense_i <= 0;
                d2w_addr <= dense_o;
                state <= S_D2_ADDR;
            end

            S_D2_ADDR: begin
                d2w_addr <= dense_i*9 + dense_o;
                state <= S_D2_READ;
            end

            S_D2_READ: begin
                state <= S_D2_MAC;
            end

            S_D2_MAC: begin
                sum <= sum + $signed(dense1_out[dense_i]) * $signed(d2w_rdata);

                if (dense_i==63) begin dense_i<=0; state<=S_D2_SAVE; end
                else begin dense_i<=dense_i+1; state<=S_D2_ADDR; end
            end

            S_D2_SAVE: begin
                dense2_out[dense_o] <= sum;
                if (dense_o==8) begin dense_o<=0;
                    state<=S_ARGMAX_INIT; $display("dense2 done");
                end else begin dense_o<=dense_o+1; state<=S_D2_INIT; end
            end

            // ── ARGMAX ────────────────────────────────────────
            S_ARGMAX_INIT: begin
                max_val   <= dense2_out[0];
                class_idx <= 0;
                arg_i     <= 1;
                state     <= S_ARGMAX_SCAN;
            end

            S_ARGMAX_SCAN: begin
                if (dense2_out[arg_i] > max_val) begin
                    max_val   <= dense2_out[arg_i];
                    class_idx <= arg_i;
                end
                if (arg_i==8) state<=S_DONE;
                else arg_i<=arg_i+1;
            end

            S_DONE: begin
                done <= 1; busy <= 0;
                $display("FSM done. class=%0d", class_idx);
                state <= S_IDLE;
            end

            default: state <= S_IDLE;
            endcase
        end
    end

endmodule