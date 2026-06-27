// ============================================================
// dense.v
//
// [수정] conv와 동일한 S_ADDR→S_WAIT→S_MAC 3단계 구조
//   S_INIT : acc=bias, in_n=0
//   S_ADDR : ibram_addr <= in_n  (주소 세팅, 1사이클)
//   S_WAIT : 1사이클 대기        (BRAM rdata 유효화)
//   S_MAC  : acc += rdata*w, in_n++ → S_ADDR or S_WRITE
// ============================================================

// ── Dense0: 1152 → 64, ReLU ──────────────────────────────────
module dense0_layer (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,

    output reg  [10:0] ibram_addr,
    input  wire [7:0]  ibram_rdata,

    output reg  [5:0]  obram_addr,
    output reg  [7:0]  obram_wdata,
    output reg         obram_we,

    output reg         done
);

localparam N_IN  = 1152;
localparam N_OUT = 64;

reg signed [7:0] weight_flat [0:73727];
reg signed [7:0] bias_mem    [0:63];

initial begin
    $readmemh("dense0_weight.txt", weight_flat);
    $readmemh("dense0_bias.txt",   bias_mem);
end

localparam S_IDLE   = 3'd0;
localparam S_INIT   = 3'd1;
localparam S_ADDR   = 3'd2;
localparam S_WAIT   = 3'd3;
localparam S_MAC    = 3'd4;
localparam S_WRITE  = 3'd5;
localparam S_OUTNXT = 3'd6;
localparam S_DONE   = 3'd7;

reg [2:0]  state;
reg [10:0] in_n;
reg [5:0]  out_n;
reg signed [31:0] acc;

wire [16:0] widx = ({6'b0, in_n} * 7'd64) + {11'b0, out_n};

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
        in_n<=0; out_n<=0; acc<=0;
        ibram_addr<=0; obram_addr<=0; obram_wdata<=0;
    end else begin
        obram_we<=0; done<=0;
        case (state)
            S_IDLE: begin
                if (start) begin out_n<=0; state<=S_INIT; end
            end
            S_INIT: begin
                acc   <= {{24{bias_mem[out_n][7]}}, bias_mem[out_n]};
                in_n  <= 0;
                state <= S_ADDR;
            end
            S_ADDR: begin
                ibram_addr <= in_n;
                state      <= S_WAIT;
            end
            S_WAIT: begin
                state <= S_MAC;
            end
            S_MAC: begin
                acc <= acc + $signed({1'b0, ibram_rdata})
                           * $signed(weight_flat[widx]);
                if (in_n == N_IN-1) begin
                    in_n  <= 0;
                    state <= S_WRITE;
                end else begin
                    in_n  <= in_n + 1;
                    state <= S_ADDR;
                end
            end
            S_WRITE: begin
                obram_wdata <= relu_clamp(acc >>> 12); // >>7→>>12: 1152항 축적 포화 방지
                obram_addr  <= out_n;
                obram_we    <= 1;
                state       <= S_OUTNXT;
            end
            S_OUTNXT: begin
                if (out_n == N_OUT-1) state <= S_DONE;
                else begin out_n<=out_n+1; state<=S_INIT; end
            end
            S_DONE: begin done<=1; state<=S_IDLE; end
        endcase
    end
end

endmodule


// ── Dense1: 64 → 9, ReLU 없음 ────────────────────────────────
module dense1_layer (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,

    output reg  [5:0]  ibram_addr,
    input  wire [7:0]  ibram_rdata,

    output reg  [3:0]  obram_addr,
    output reg  [7:0]  obram_wdata,
    output reg         obram_we,

    output reg         done
);

localparam N_IN  = 64;
localparam N_OUT = 9;

reg signed [7:0] weight_flat [0:575];
reg signed [7:0] bias_mem    [0:8];

initial begin
    $readmemh("dense1_weight.txt", weight_flat);
    $readmemh("dense1_bias.txt",   bias_mem);
end

localparam S_IDLE   = 3'd0;
localparam S_INIT   = 3'd1;
localparam S_ADDR   = 3'd2;
localparam S_WAIT   = 3'd3;
localparam S_MAC    = 3'd4;
localparam S_WRITE  = 3'd5;
localparam S_OUTNXT = 3'd6;
localparam S_DONE   = 3'd7;

reg [2:0] state;
reg [5:0] in_n;
reg [3:0] out_n;
reg signed [31:0] acc;

wire [9:0] widx = ({4'b0, in_n} * 4'd9) + {6'b0, out_n};

function [7:0] signed_clamp;
    input signed [31:0] v;
    begin
        if      (v >  127) signed_clamp = 8'h7f;
        else if (v < -128) signed_clamp = 8'h80;
        else               signed_clamp = v[7:0];
    end
endfunction

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state<=S_IDLE; done<=0; obram_we<=0;
        in_n<=0; out_n<=0; acc<=0;
        ibram_addr<=0; obram_addr<=0; obram_wdata<=0;
    end else begin
        obram_we<=0; done<=0;
        case (state)
            S_IDLE: begin
                if (start) begin out_n<=0; state<=S_INIT; end
            end
            S_INIT: begin
                acc   <= {{24{bias_mem[out_n][7]}}, bias_mem[out_n]};
                in_n  <= 0;
                state <= S_ADDR;
            end
            S_ADDR: begin
                ibram_addr <= in_n;
                state      <= S_WAIT;
            end
            S_WAIT: begin
                state <= S_MAC;
            end
            S_MAC: begin
                acc <= acc + $signed({1'b0, ibram_rdata})
                           * $signed(weight_flat[widx]);
                if (in_n == N_IN-1) begin
                    in_n  <= 0;
                    state <= S_WRITE;
                end else begin
                    in_n  <= in_n + 1;
                    state <= S_ADDR;
                end
            end
            S_WRITE: begin
                obram_wdata <= signed_clamp(acc >>> 12); // >>7→>>12: 64항 축적 포화 방지
                obram_addr  <= out_n;
                obram_we    <= 1;
                state       <= S_OUTNXT;
            end
            S_OUTNXT: begin
                if (out_n == N_OUT-1) state <= S_DONE;
                else begin out_n<=out_n+1; state<=S_INIT; end
            end
            S_DONE: begin done<=1; state<=S_IDLE; end
        endcase
    end
end

endmodule