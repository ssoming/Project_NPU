// ============================================================
// cnn_top.v  - CNN 추론 최상위 (BRAM 동기식 읽기 수정본)
//
// [핵심 수정]
//   BRAM 읽기를 동기식으로 변경 (실제 FPGA BRAM과 동일)
//   assign ba_rdata = bram_A[ba_raddr] → 비동기 → x 전파 원인
//   → always @(posedge clk) ba_rdata_reg <= bram_A[ba_raddr] 로 변경
//   → 각 서브모듈의 FETCH 상태가 이미 1사이클 대기를 포함하므로 타이밍 OK
//
// 레이어 크기 (padding=same):
//   입력         : 48×48×1  = 2304B  → bram_A
//   Conv0 출력   : 48×48×8  = 18432B → bram_B
//   MaxPool0 출력: 24×24×8  = 4608B  → bram_A
//   Conv1 출력   : 24×24×16 = 9216B  → bram_B
//   MaxPool1 출력: 12×12×16 = 2304B  → bram_A
//   Conv2 출력   : 12×12×32 = 4608B  → bram_B
//   MaxPool2 출력:  6×6×32  = 1152B  → bram_A
//   Dense0 출력  :       64B         → bram_B
//   Dense1 출력  :        9B         → bram_A
// ============================================================

module cnn_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,

    input  wire [11:0] img_addr,
    input  wire [7:0]  img_wdata,
    input  wire        img_we,

    output reg  [3:0]  result,
    output reg         done
);

// ── BRAM ─────────────────────────────────────────────────────
localparam BRAM_DEPTH = 20000;

reg [7:0] bram_A [0:BRAM_DEPTH-1];
reg [7:0] bram_B [0:BRAM_DEPTH-1];

// 포트 (동기식 읽기)
reg  [14:0] ba_raddr;
reg  [14:0] ba_waddr;
reg  [7:0]  ba_wdata;
reg         ba_we;
reg  [7:0]  ba_rdata_reg;   // 동기식 읽기 레지스터

reg  [14:0] bb_raddr;
reg  [14:0] bb_waddr;
reg  [7:0]  bb_wdata;
reg         bb_we;
reg  [7:0]  bb_rdata_reg;

// 동기식 BRAM 읽기/쓰기
always @(posedge clk) begin
    // 쓰기
    if (img_we) bram_A[img_addr] <= img_wdata;
    if (ba_we)  bram_A[ba_waddr] <= ba_wdata;
    if (bb_we)  bram_B[bb_waddr] <= bb_wdata;
    // 읽기 (동기식 - 1사이클 지연, 각 서브모듈 FETCH 상태가 수용)
    ba_rdata_reg <= bram_A[ba_raddr];
    bb_rdata_reg <= bram_B[bb_raddr];
end

// ── 서브모듈 신호 ─────────────────────────────────────────────
reg  conv0_start, pool0_start, conv1_start, pool1_start;
reg  conv2_start, pool2_start, dense0_start, dense1_start;
wire conv0_done,  pool0_done,  conv1_done,  pool1_done;
wire conv2_done,  pool2_done,  dense0_done, dense1_done;

// ── Conv0: A→B ────────────────────────────────────────────────
wire [11:0] c0_ira; wire [14:0] c0_owa; wire [7:0] c0_owd; wire c0_owe;
conv0 u_conv0 (.clk(clk),.rst_n(rst_n),.start(conv0_start),
    .ibram_addr(c0_ira),.ibram_rdata(ba_rdata_reg),
    .obram_addr(c0_owa),.obram_wdata(c0_owd),.obram_we(c0_owe),.done(conv0_done));

// ── MaxPool0: B→A ─────────────────────────────────────────────
wire [14:0] p0_ira; wire [12:0] p0_owa; wire [7:0] p0_owd; wire p0_owe;
maxpool #(.IN_H(48),.IN_W(48),.N_CH(8)) u_pool0 (
    .clk(clk),.rst_n(rst_n),.start(pool0_start),
    .ibram_addr(p0_ira),.ibram_rdata(bb_rdata_reg),
    .obram_addr(p0_owa),.obram_wdata(p0_owd),.obram_we(p0_owe),.done(pool0_done));

// ── Conv1: A→B ────────────────────────────────────────────────
wire [12:0] c1_ira; wire [13:0] c1_owa; wire [7:0] c1_owd; wire c1_owe;
conv1 u_conv1 (.clk(clk),.rst_n(rst_n),.start(conv1_start),
    .ibram_addr(c1_ira),.ibram_rdata(ba_rdata_reg),
    .obram_addr(c1_owa),.obram_wdata(c1_owd),.obram_we(c1_owe),.done(conv1_done));

// ── MaxPool1: B→A ─────────────────────────────────────────────
wire [13:0] p1_ira; wire [11:0] p1_owa; wire [7:0] p1_owd; wire p1_owe;
maxpool #(.IN_H(24),.IN_W(24),.N_CH(16)) u_pool1 (
    .clk(clk),.rst_n(rst_n),.start(pool1_start),
    .ibram_addr(p1_ira),.ibram_rdata(bb_rdata_reg),
    .obram_addr(p1_owa),.obram_wdata(p1_owd),.obram_we(p1_owe),.done(pool1_done));

// ── Conv2: A→B ────────────────────────────────────────────────
wire [11:0] c2_ira; wire [12:0] c2_owa; wire [7:0] c2_owd; wire c2_owe;
conv2 u_conv2 (.clk(clk),.rst_n(rst_n),.start(conv2_start),
    .ibram_addr(c2_ira),.ibram_rdata(ba_rdata_reg),
    .obram_addr(c2_owa),.obram_wdata(c2_owd),.obram_we(c2_owe),.done(conv2_done));

// ── MaxPool2: B→A ─────────────────────────────────────────────
wire [12:0] p2_ira; wire [10:0] p2_owa; wire [7:0] p2_owd; wire p2_owe;
maxpool #(.IN_H(12),.IN_W(12),.N_CH(32)) u_pool2 (
    .clk(clk),.rst_n(rst_n),.start(pool2_start),
    .ibram_addr(p2_ira),.ibram_rdata(bb_rdata_reg),
    .obram_addr(p2_owa),.obram_wdata(p2_owd),.obram_we(p2_owe),.done(pool2_done));

// ── Dense0: A→B (1152→64, ReLU) ──────────────────────────────
wire [10:0] d0_ira; wire [5:0] d0_owa; wire [7:0] d0_owd; wire d0_owe;
dense0_layer u_dense0 (
    .clk(clk),.rst_n(rst_n),.start(dense0_start),
    .ibram_addr(d0_ira),.ibram_rdata(ba_rdata_reg),
    .obram_addr(d0_owa),.obram_wdata(d0_owd),.obram_we(d0_owe),.done(dense0_done));

// ── Dense1: B→A (64→9, no ReLU) ──────────────────────────────
wire [5:0] d1_ira; wire [3:0] d1_owa; wire [7:0] d1_owd; wire d1_owe;
dense1_layer u_dense1 (
    .clk(clk),.rst_n(rst_n),.start(dense1_start),
    .ibram_addr(d1_ira),.ibram_rdata(bb_rdata_reg),
    .obram_addr(d1_owa),.obram_wdata(d1_owd),.obram_we(d1_owe),.done(dense1_done));

// ── Top FSM ───────────────────────────────────────────────────
localparam ST_IDLE   = 4'd0;
localparam ST_CONV0  = 4'd1;
localparam ST_POOL0  = 4'd2;
localparam ST_CONV1  = 4'd3;
localparam ST_POOL1  = 4'd4;
localparam ST_CONV2  = 4'd5;
localparam ST_POOL2  = 4'd6;
localparam ST_DENSE0 = 4'd7;
localparam ST_DENSE1 = 4'd8;
localparam ST_ARGMAX = 4'd9;
localparam ST_DONE   = 4'd10;

reg [3:0] top_st;
reg [3:0] argmax_cnt;
reg signed [7:0] max_score;
reg [3:0] max_idx;

// ── BRAM 포트 먹싱 ────────────────────────────────────────────
always @(*) begin
    // A 포트 기본값
    ba_raddr = 0; ba_waddr = 0; ba_wdata = 0; ba_we = 0;
    case (top_st)
        ST_CONV0:  ba_raddr = c0_ira;
        ST_POOL0:  begin ba_waddr = p0_owa; ba_wdata = p0_owd; ba_we = p0_owe; end
        ST_CONV1:  ba_raddr = c1_ira;
        ST_POOL1:  begin ba_waddr = p1_owa; ba_wdata = p1_owd; ba_we = p1_owe; end
        ST_CONV2:  ba_raddr = c2_ira;
        ST_POOL2:  begin ba_waddr = p2_owa; ba_wdata = p2_owd; ba_we = p2_owe; end
        ST_DENSE0: ba_raddr = d0_ira;
        ST_DENSE1: begin ba_waddr = d1_owa; ba_wdata = d1_owd; ba_we = d1_owe; end
        ST_ARGMAX: ba_raddr = argmax_cnt;
        default:   ;
    endcase
end

always @(*) begin
    // B 포트 기본값
    bb_raddr = 0; bb_waddr = 0; bb_wdata = 0; bb_we = 0;
    case (top_st)
        ST_CONV0:  begin bb_waddr = c0_owa; bb_wdata = c0_owd; bb_we = c0_owe; end
        ST_POOL0:  bb_raddr = p0_ira;
        ST_CONV1:  begin bb_waddr = c1_owa; bb_wdata = c1_owd; bb_we = c1_owe; end
        ST_POOL1:  bb_raddr = p1_ira;
        ST_CONV2:  begin bb_waddr = c2_owa; bb_wdata = c2_owd; bb_we = c2_owe; end
        ST_POOL2:  bb_raddr = p2_ira;
        ST_DENSE0: begin bb_waddr = d0_owa; bb_wdata = d0_owd; bb_we = d0_owe; end
        ST_DENSE1: bb_raddr = d1_ira;
        default:   ;
    endcase
end

// ── Top FSM 본체 ─────────────────────────────────────────────
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        top_st <= ST_IDLE; done <= 0; result <= 0;
        conv0_start<=0; pool0_start<=0; conv1_start<=0; pool1_start<=0;
        conv2_start<=0; pool2_start<=0; dense0_start<=0; dense1_start<=0;
        argmax_cnt<=0; max_score<=-128; max_idx<=0;
    end else begin
        conv0_start<=0; pool0_start<=0; conv1_start<=0; pool1_start<=0;
        conv2_start<=0; pool2_start<=0; dense0_start<=0; dense1_start<=0;
        done <= 0;

        case (top_st)
            ST_IDLE:   if (start)       begin conv0_start<=1;  top_st<=ST_CONV0;  end
            ST_CONV0:  if (conv0_done)  begin pool0_start<=1;  top_st<=ST_POOL0;  end
            ST_POOL0:  if (pool0_done)  begin conv1_start<=1;  top_st<=ST_CONV1;  end
            ST_CONV1:  if (conv1_done)  begin pool1_start<=1;  top_st<=ST_POOL1;  end
            ST_POOL1:  if (pool1_done)  begin conv2_start<=1;  top_st<=ST_CONV2;  end
            ST_CONV2:  if (conv2_done)  begin pool2_start<=1;  top_st<=ST_POOL2;  end
            ST_POOL2:  if (pool2_done)  begin dense0_start<=1; top_st<=ST_DENSE0; end
            ST_DENSE0: if (dense0_done) begin dense1_start<=1; top_st<=ST_DENSE1; end
            ST_DENSE1: if (dense1_done) begin
                argmax_cnt<=0; max_score<=-128; max_idx<=0;
                top_st<=ST_ARGMAX;
            end

            // Argmax: bram_A[0~8] (Dense1 출력)
            // 동기식 BRAM: 주소 세팅 후 1사이클 지연
            ST_ARGMAX: begin
                argmax_cnt <= argmax_cnt + 1;
                // argmax_cnt=0: addr=0 세팅
                // argmax_cnt=1: rdata=bram_A[0] 유효 → 비교
                if (argmax_cnt >= 1) begin
                    if ($signed(ba_rdata_reg) > max_score) begin
                        max_score <= $signed(ba_rdata_reg);
                        max_idx   <= argmax_cnt - 1;
                    end
                end
                if (argmax_cnt == 10) top_st <= ST_DONE;  // 9개+여유1
            end

            ST_DONE: begin
                result  <= max_idx;
                done    <= 1;
                top_st  <= ST_IDLE;
            end
        endcase
    end
end

endmodule