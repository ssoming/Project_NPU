`timescale 1ns / 1ps

module uart_rx_core(
    input  wire        clk,
    input  wire        rst,
    input  wire        rx,
    input  wire [31:0] baud_div,
    output reg  [7:0]  rx_data,
    output reg         rx_busy,
    output reg         rx_done,
    output reg         rx_error      // Stop bit 오류 플래그
    );
    
    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;
    
    reg [1:0]  state;
    reg [31:0] baud_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  data_buf;
//    reg [13:0] acc;
//    reg [1:0] digit_cnt;
    
    // ── 2FF 동기화 (메타스태빌리티 방지) ──
    reg rx_ff1, rx_ff2;
    always @(posedge clk) begin
        if(!rst) begin
            rx_ff1 <= 1'b1;
            rx_ff2 <= 1'b1;
        end else begin
            rx_ff1 <= rx;
            rx_ff2 <= rx_ff1;
        end
    end
    wire rx_sync = rx_ff2;
    
    always @(posedge clk or negedge rst) begin
        if(!rst) begin
            state    <= IDLE;
            baud_cnt <= 32'd0;
            bit_idx  <= 3'd0;
            data_buf <= 8'd0;
            rx_data  <= 8'd0;
            rx_busy  <= 1'b0;
            rx_done  <= 1'b0;
            rx_error <= 1'b0;
//            acc <= 14'd0;
//            digit_cnt <= 2'd0;
        end else begin
            rx_done  <= 1'b0;   // TX의 tx_done과 동일하게 1클럭 펄스
            rx_error <= 1'b0;
            
            case(state)
                IDLE: begin
                    rx_busy  <= 1'b0;
                    baud_cnt <= 32'd0;
                    bit_idx  <= 3'd0;
                    
                    if(!rx_sync) begin          // Start bit 감지 (High→Low)
                        state   <= START;
                        rx_busy <= 1'b1;
                    end
                end
                
                START: begin
                    // TX 방식과 동일하게 baud_div/2 지점에서 중앙 샘플링
                    // → Start bit 중앙에서 실제 Start인지 노이즈인지 확인
                    if(baud_cnt >= baud_div >> 1) begin
                        baud_cnt <= 32'd0;
                        if(!rx_sync)            // Start bit 중앙 재확인
                            state <= DATA;
                        else                    // 노이즈 → IDLE 복귀
                            state <= IDLE;
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end
                
                DATA: begin
                    // baud_div 주기마다 중앙 샘플링 (START에서 이미 반 클럭 소모)
                    if(baud_cnt >= baud_div) begin
                        baud_cnt           <= 32'd0;
                        data_buf[bit_idx]  <= rx_sync; // LSB first (TX와 동일)
                        
                        if(bit_idx == 3'd7) begin
                            bit_idx <= 3'd0;
                            state   <= STOP;
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end
                
                STOP: begin
                    if(baud_cnt >= baud_div) begin
                        baud_cnt <= 32'd0;
                        state    <= IDLE;
                        rx_busy  <= 1'b0;
                        
                        if(rx_sync) begin       // Stop bit 정상 (High)
                            rx_data <= data_buf;
                            rx_done <= 1'b1;    // TX의 tx_done과 동일한 완료 펄스
//                            acc <= acc * 10 + (data_buf - 8'h30);
//                            digit_cnt <= digit_cnt + 1;
//                            if(digit_cnt == 2'd3) begin
//                                rx_data <= acc * 10 + (data_buf - 8'h30);
//                                rx_done <= 1'b1;
//                                digit_cnt <= 2'd0;
//                                acc <= 14'd0;
//                            end
                        end else begin          // Stop bit 오류 → 프레임 에러
                            rx_error <= 1'b1;
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end
                
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule



module uart_tx_core(
    input wire clk,
    input wire rst,
    input wire [7:0] tx_data,
    input wire tx_start,
    input wire [31:0] baud_div,
    output reg tx,
    output reg tx_busy,
    output reg tx_done
    );
    
    localparam IDLE = 2'd0;
    localparam START = 2'd1;
    localparam DATA = 2'd2;
    localparam STOP = 2'd3;
    
    reg [1:0] state;
    reg [31:0] baud_cnt;
    reg [2:0] bit_idx;
    reg [7:0] data_buf;
    
    always @(posedge clk or negedge rst) begin
        if(!rst) begin
            state <= IDLE;
            baud_cnt <= 32'd0;
            bit_idx <= 3'd0;
            data_buf <= 8'd0;
            tx <= 1'b1;
            tx_busy <= 1'b0;
            tx_done <= 1'b0;
        end else begin
            tx_done <= 1'b0;
            
            case (state)
                IDLE: begin
                    tx <= 1'b1;
                    tx_busy <= 1'b0;
                    baud_cnt <= 32'd0;
                    bit_idx <= 3'd0;
                
                
                if(tx_start) begin
                    state <= START;
                    tx_busy <= 1'b1;
                    data_buf <= tx_data;
                end
            end
            
                START: begin
                    tx <= 1'b0;
                    if(baud_cnt >= baud_div) begin
                        baud_cnt <= 32'd0;
                        state <= DATA;
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end
                
                DATA: begin
                    tx <= data_buf[bit_idx];
                    if(baud_cnt >= baud_div) begin
                        baud_cnt <= 32'd0;
                        if(bit_idx == 3'd7) begin
                            bit_idx <= 3'd0;
                            state <= STOP;
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end
                
                STOP: begin
                    tx <= 1'b1;
                    if(baud_cnt >= baud_div) begin
                        baud_cnt <= 32'b0;
                        state <= IDLE;
                        tx_busy <= 1'b0;
                        tx_done <= 1'b1;
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end
                
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule
