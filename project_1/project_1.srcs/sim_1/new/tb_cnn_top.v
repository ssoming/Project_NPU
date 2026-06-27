`timescale 1ns/1ps
module tb_cnn_top;

reg clk, rst_n;
always #5 clk = ~clk;

reg  [11:0] img_addr;
reg  [7:0]  img_wdata;
reg         img_we;
wire [3:0]  result;
wire        done;
reg         start;

cnn_top dut (
    .clk(clk),.rst_n(rst_n),.start(start),
    .img_addr(img_addr),.img_wdata(img_wdata),.img_we(img_we),
    .result(result),.done(done)
);

reg [7:0] img_buf [0:2303];
integer i, timeout_cnt;
localparam TIMEOUT = 100_000_000;

initial begin
    clk=0; rst_n=0; start=0; img_we=0; img_addr=0; img_wdata=0;
    repeat(10) @(posedge clk); rst_n=1; repeat(5) @(posedge clk);
    $readmemh("test_image.txt", img_buf);
    for (i=0; i<2304; i=i+1) begin
        @(posedge clk); img_we<=1; img_addr<=i; img_wdata<=img_buf[i];
    end
    @(posedge clk); img_we<=0;
    $display("[TB] 이미지 기록 완료");
    repeat(3) @(posedge clk);
    @(posedge clk); start<=1; @(posedge clk); start<=0;
    $display("[TB] 추론 시작");
    timeout_cnt=0;
    while (!done && timeout_cnt < TIMEOUT) begin
        @(posedge clk); timeout_cnt=timeout_cnt+1;
    end
    if (timeout_cnt >= TIMEOUT) begin $display("[TB] TIMEOUT"); $finish; end
    @(posedge clk);
    $display("[TB] 완료 cycles=%0d 예측=%0d 기대=2", timeout_cnt, result);
    if (result==4'd2) $display("[TB] PASS"); else $display("[TB] FAIL");
    $finish;
end

reg [3:0] prev_st;
always @(posedge clk) begin
    if (rst_n && dut.top_st !== prev_st) begin
        case (dut.top_st)
            4'd1: $display("[TB] CONV0  시작");
            4'd2: $display("[TB] POOL0  시작");
            4'd3: $display("[TB] CONV1  시작");
            4'd4: $display("[TB] POOL1  시작");
            4'd5: $display("[TB] CONV2  시작");
            4'd6: $display("[TB] POOL2  시작");
            4'd7: $display("[TB] DENSE0 시작");
            4'd8: $display("[TB] DENSE1 시작");
            4'd9: $display("[TB] ARGMAX 시작");
        endcase
        prev_st <= dut.top_st;
    end
end

// ── Conv0 완료: bram_B[0~3] ─────────────────────────────
always @(posedge clk) begin
    if (dut.pool0_start)
        $display("[TB] Conv0→bram_B[0]=%02x [1]=%02x [2]=%02x [3]=%02x (기대:7c ff ff f2)",
            dut.bram_B[0],dut.bram_B[1],dut.bram_B[2],dut.bram_B[3]);
end

// ── Pool0 완료: bram_A[0~3] (24×24×8 채널0 첫 픽셀들) ──
always @(posedge clk) begin
    if (dut.conv1_start)
        $display("[TB] Pool0→bram_A[0]=%02x [1]=%02x [2]=%02x [3]=%02x",
            dut.bram_A[0],dut.bram_A[1],dut.bram_A[2],dut.bram_A[3]);
end

// ── Pool2 완료: bram_A[0~3] (6×6×32 flatten 첫값들) ────
always @(posedge clk) begin
    if (dut.dense0_start)
        $display("[TB] Pool2→bram_A[0]=%02x [1]=%02x [2]=%02x [3]=%02x",
            dut.bram_A[0],dut.bram_A[1],dut.bram_A[2],dut.bram_A[3]);
end

// ── Dense0 첫 write (bram_B write 신호 직접 모니터) ─────
always @(posedge clk) begin
    if (dut.bb_we && dut.top_st==4'd7)
        $display("[TB] Dense0 bb_we=1 bb_waddr=%0d bb_wdata=%02x",
            dut.bb_waddr, dut.bb_wdata);
end

// ── Dense0 ibram_rdata 첫 몇 개 확인 ────────────────────
reg [3:0] d0_mac_cnt;
always @(posedge clk) begin
    if (!rst_n) d0_mac_cnt <= 0;
    else if (dut.top_st==4'd7 && dut.u_dense0.state==3'd4 && d0_mac_cnt<4) begin
        $display("[TB] Dense0 S_MAC: in_n=%0d ibram_rdata=%02x widx=%0d weight=%02x",
            dut.u_dense0.in_n, dut.u_dense0.ibram_rdata,
            dut.u_dense0.widx, dut.u_dense0.weight_flat[dut.u_dense0.widx]);
        d0_mac_cnt <= d0_mac_cnt + 1;
    end
end

endmodule