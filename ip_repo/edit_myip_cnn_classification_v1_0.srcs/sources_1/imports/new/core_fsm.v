`timescale 1ns / 1ps

module cnn_core_fsm(
    input  wire clk,
    input  wire reset_p,

    input  wire start,
    output reg  done,
    output reg  busy,
    output reg  [3:0] class_idx,

    input  wire img_we,
    input  wire [11:0] img_addr,
    input  wire signed [15:0] img_wdata
);

    localparam BN_SHIFT = 16;

    localparam S_IDLE        = 5'd0;

    localparam S_CONV1_INIT  = 5'd1;
    localparam S_CONV1_MAC   = 5'd2;
    localparam S_CONV1_SAVE  = 5'd3;
    localparam S_POOL1       = 5'd4;

    localparam S_CONV2_INIT  = 5'd5;
    localparam S_CONV2_MAC   = 5'd6;
    localparam S_CONV2_SAVE  = 5'd7;
    localparam S_POOL2       = 5'd8;

    localparam S_CONV3_INIT  = 5'd9;
    localparam S_CONV3_MAC   = 5'd10;
    localparam S_CONV3_SAVE  = 5'd11;
    localparam S_POOL3       = 5'd12;

    localparam S_DENSE1_INIT = 5'd13;
    localparam S_DENSE1_MAC  = 5'd14;
    localparam S_DENSE1_SAVE = 5'd15;

    localparam S_DENSE2_INIT = 5'd16;
    localparam S_DENSE2_MAC  = 5'd17;
    localparam S_DENSE2_SAVE = 5'd18;

    localparam S_ARGMAX_INIT = 5'd19;
    localparam S_ARGMAX_SCAN = 5'd20;
    localparam S_DONE        = 5'd21;

    reg [4:0] state;

    // ============================================================
    // Model parameter memories
    // ============================================================

    reg signed [15:0] img_mem [0:48*48-1];

    reg signed [7:0]  conv1_w [0:72-1];
    reg signed [63:0] conv1_b [0:8-1];
    reg signed [31:0] bn1_mul [0:8-1];
    reg signed [31:0] bn1_add [0:8-1];

    reg signed [7:0]  conv2_w [0:1152-1];
    reg signed [63:0] conv2_b [0:16-1];
    reg signed [31:0] bn2_mul [0:16-1];
    reg signed [31:0] bn2_add [0:16-1];

    reg signed [7:0]  conv3_w [0:4608-1];
    reg signed [63:0] conv3_b [0:32-1];
    reg signed [31:0] bn3_mul [0:32-1];
    reg signed [31:0] bn3_add [0:32-1];

    reg signed [7:0]  dense1_w [0:73728-1];
    reg signed [63:0] dense1_b [0:64-1];

    reg signed [7:0]  dense2_w [0:576-1];
    reg signed [63:0] dense2_b [0:9-1];

    // ============================================================
    // Feature map memories
    // ============================================================

    reg signed [31:0] fm1   [0:48*48*8-1];
    reg signed [31:0] pool1 [0:24*24*8-1];

    reg signed [31:0] fm2   [0:24*24*16-1];
    reg signed [31:0] pool2 [0:12*12*16-1];

    reg signed [31:0] fm3   [0:12*12*32-1];
    reg signed [31:0] pool3 [0:6*6*32-1];

    reg signed [63:0] dense1_out [0:64-1];
    reg signed [63:0] dense2_out [0:9-1];

    // ============================================================
    // File load
    // ============================================================

    initial begin
        $display("FSM CNN: Loading mem files...");

        $readmemh("conv1_w.mem", conv1_w);
        $readmemh("conv1_b.mem", conv1_b);
        $readmemh("bn1_mul.mem", bn1_mul);
        $readmemh("bn1_add.mem", bn1_add);

        $readmemh("conv2_w.mem", conv2_w);
        $readmemh("conv2_b.mem", conv2_b);
        $readmemh("bn2_mul.mem", bn2_mul);
        $readmemh("bn2_add.mem", bn2_add);
        
        $readmemh("conv3_w.mem", conv3_w);
        $readmemh("conv3_b.mem", conv3_b);
        $readmemh("bn3_mul.mem", bn3_mul);
        $readmemh("bn3_add.mem", bn3_add);

        $readmemh("dense1_w.mem", dense1_w);
        $readmemh("dense1_b.mem", dense1_b);

        $readmemh("dense2_w.mem", dense2_w);
        $readmemh("dense2_b.mem", dense2_b);

        $display("FSM CNN: Mem load done.");
    end

    // ============================================================
    // Image write port
    // ============================================================

    always @(posedge clk) begin
        if (img_we && !busy) begin
            img_mem[img_addr] <= img_wdata;
        end
    end

    // ============================================================
    // Index functions
    // ============================================================

    function integer fm_idx;
        input integer h;
        input integer w;
        input integer c;
        input integer width;
        input integer channels;
        begin
            fm_idx = (h * width + w) * channels + c;
        end
    endfunction

    function integer conv_w_idx;
        input integer kh_i;
        input integer kw_i;
        input integer ic_i;
        input integer oc_i;
        input integer cin_i;
        input integer cout_i;
        begin
            conv_w_idx = (((kh_i * 3 + kw_i) * cin_i + ic_i) * cout_i + oc_i);
        end
    endfunction

    function integer dense_w_idx;
        input integer in_i;
        input integer out_i;
        input integer out_dim;
        begin
            dense_w_idx = in_i * out_dim + out_i;
        end
    endfunction

    // ============================================================
    // Counters and temporary regs
    // ============================================================

    reg [5:0] oh;
    reg [5:0] ow;
    reg [5:0] oc;
    reg [5:0] ic;

    reg [1:0] kh;
    reg [1:0] kw;

    reg [5:0] ph;
    reg [5:0] pw;
    reg [5:0] pc;

    reg [11:0] dense_i;
    reg [6:0]  dense_o;

    reg [3:0] arg_i;

    integer ih;
    integer iw;
    integer in_index;
    integer w_index;
    integer out_index;

    integer p_ih;
    integer p_iw;
    integer idx0;
    integer idx1;
    integer idx2;
    integer idx3;
    integer pool_out_index;

    reg signed [63:0] sum;
    reg signed [63:0] relu_sum;
    reg signed [95:0] bn_mult;
    reg signed [31:0] pool_max;

    reg signed [63:0] max_val;

    // ============================================================
    // Main FSM
    // ============================================================

    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin
            state <= S_IDLE;

            done <= 0;
            busy <= 0;
            class_idx <= 0;

            oh <= 0;
            ow <= 0;
            oc <= 0;
            ic <= 0;
            kh <= 0;
            kw <= 0;

            ph <= 0;
            pw <= 0;
            pc <= 0;

            dense_i <= 0;
            dense_o <= 0;
            arg_i <= 0;

            sum <= 0;
            max_val <= 0;
        end else begin
            case (state)

                S_IDLE: begin
                    done <= 0;

                    if (start && !busy) begin
                        busy <= 1;
                        class_idx <= 0;

                        oh <= 0;
                        ow <= 0;
                        oc <= 0;
                        ic <= 0;
                        kh <= 0;
                        kw <= 0;

                        ph <= 0;
                        pw <= 0;
                        pc <= 0;

                        dense_i <= 0;
                        dense_o <= 0;
                        arg_i <= 0;

                        state <= S_CONV1_INIT;

                        $display("FSM CNN start");
                    end
                end

                // =================================================
                // Conv1 + ReLU + BN
                // Input: 48x48x1
                // Output: 48x48x8
                // =================================================

                S_CONV1_INIT: begin
                    sum <= conv1_b[oc];

                    kh <= 0;
                    kw <= 0;

                    state <= S_CONV1_MAC;
                end

                S_CONV1_MAC: begin
                    ih = oh + kh - 1;
                    iw = ow + kw - 1;

                    if ((ih >= 0) && (ih < 48) && (iw >= 0) && (iw < 48)) begin
                        in_index = ih * 48 + iw;
                        w_index = conv_w_idx(kh, kw, 0, oc, 1, 8);

                        sum <= sum + $signed(img_mem[in_index]) * $signed(conv1_w[w_index]);
                    end

                    if (kw == 2) begin
                        kw <= 0;

                        if (kh == 2) begin
                            kh <= 0;
                            state <= S_CONV1_SAVE;
                        end else begin
                            kh <= kh + 1;
                        end
                    end else begin
                        kw <= kw + 1;
                    end
                end

                S_CONV1_SAVE: begin
                    if (sum < 0)
                        relu_sum = 0;
                    else
                        relu_sum = sum;

                    bn_mult = relu_sum * $signed(bn1_mul[oc]);
                    out_index = fm_idx(oh, ow, oc, 48, 8);

                    fm1[out_index] <= (bn_mult >>> BN_SHIFT) + $signed(bn1_add[oc]);

                    if (oc == 7) begin
                        oc <= 0;

                        if (ow == 47) begin
                            ow <= 0;

                            if (oh == 47) begin
                                oh <= 0;

                                ph <= 0;
                                pw <= 0;
                                pc <= 0;

                                state <= S_POOL1;

                                $display("FSM conv1_bn done");
                            end else begin
                                oh <= oh + 1;
                                state <= S_CONV1_INIT;
                            end
                        end else begin
                            ow <= ow + 1;
                            state <= S_CONV1_INIT;
                        end
                    end else begin
                        oc <= oc + 1;
                        state <= S_CONV1_INIT;
                    end
                end

                // =================================================
                // Pool1
                // 48x48x8 -> 24x24x8
                // =================================================

                S_POOL1: begin
                    p_ih = ph * 2;
                    p_iw = pw * 2;

                    idx0 = fm_idx(p_ih,     p_iw,     pc, 48, 8);
                    idx1 = fm_idx(p_ih,     p_iw + 1, pc, 48, 8);
                    idx2 = fm_idx(p_ih + 1, p_iw,     pc, 48, 8);
                    idx3 = fm_idx(p_ih + 1, p_iw + 1, pc, 48, 8);

                    pool_max = fm1[idx0];
                    if (fm1[idx1] > pool_max) pool_max = fm1[idx1];
                    if (fm1[idx2] > pool_max) pool_max = fm1[idx2];
                    if (fm1[idx3] > pool_max) pool_max = fm1[idx3];

                    pool_out_index = fm_idx(ph, pw, pc, 24, 8);
                    pool1[pool_out_index] <= pool_max;

                    if (pc == 7) begin
                        pc <= 0;

                        if (pw == 23) begin
                            pw <= 0;

                            if (ph == 23) begin
                                ph <= 0;

                                oh <= 0;
                                ow <= 0;
                                oc <= 0;
                                ic <= 0;
                                kh <= 0;
                                kw <= 0;

                                state <= S_CONV2_INIT;

                                $display("FSM pool1 done");
                            end else begin
                                ph <= ph + 1;
                            end
                        end else begin
                            pw <= pw + 1;
                        end
                    end else begin
                        pc <= pc + 1;
                    end
                end

                // =================================================
                // Conv2 + ReLU + BN
                // Input: 24x24x8
                // Output: 24x24x16
                // =================================================

                S_CONV2_INIT: begin
                    sum <= conv2_b[oc];

                    kh <= 0;
                    kw <= 0;
                    ic <= 0;

                    state <= S_CONV2_MAC;
                end

                S_CONV2_MAC: begin
                    ih = oh + kh - 1;
                    iw = ow + kw - 1;

                    if ((ih >= 0) && (ih < 24) && (iw >= 0) && (iw < 24)) begin
                        in_index = fm_idx(ih, iw, ic, 24, 8);
                        w_index = conv_w_idx(kh, kw, ic, oc, 8, 16);

                        sum <= sum + $signed(pool1[in_index]) * $signed(conv2_w[w_index]);
                    end

                    if (ic == 7) begin
                        ic <= 0;

                        if (kw == 2) begin
                            kw <= 0;

                            if (kh == 2) begin
                                kh <= 0;
                                state <= S_CONV2_SAVE;
                            end else begin
                                kh <= kh + 1;
                            end
                        end else begin
                            kw <= kw + 1;
                        end
                    end else begin
                        ic <= ic + 1;
                    end
                end

                S_CONV2_SAVE: begin
                    if (sum < 0)
                        relu_sum = 0;
                    else
                        relu_sum = sum;

                    bn_mult = relu_sum * $signed(bn2_mul[oc]);
                    out_index = fm_idx(oh, ow, oc, 24, 16);

                    fm2[out_index] <= (bn_mult >>> BN_SHIFT) + $signed(bn2_add[oc]);

                    if (oc == 15) begin
                        oc <= 0;

                        if (ow == 23) begin
                            ow <= 0;

                            if (oh == 23) begin
                                oh <= 0;

                                ph <= 0;
                                pw <= 0;
                                pc <= 0;

                                state <= S_POOL2;

                                $display("FSM conv2_bn done");
                            end else begin
                                oh <= oh + 1;
                                state <= S_CONV2_INIT;
                            end
                        end else begin
                            ow <= ow + 1;
                            state <= S_CONV2_INIT;
                        end
                    end else begin
                        oc <= oc + 1;
                        state <= S_CONV2_INIT;
                    end
                end

                // =================================================
                // Pool2
                // 24x24x16 -> 12x12x16
                // =================================================

                S_POOL2: begin
                    p_ih = ph * 2;
                    p_iw = pw * 2;

                    idx0 = fm_idx(p_ih,     p_iw,     pc, 24, 16);
                    idx1 = fm_idx(p_ih,     p_iw + 1, pc, 24, 16);
                    idx2 = fm_idx(p_ih + 1, p_iw,     pc, 24, 16);
                    idx3 = fm_idx(p_ih + 1, p_iw + 1, pc, 24, 16);

                    pool_max = fm2[idx0];
                    if (fm2[idx1] > pool_max) pool_max = fm2[idx1];
                    if (fm2[idx2] > pool_max) pool_max = fm2[idx2];
                    if (fm2[idx3] > pool_max) pool_max = fm2[idx3];

                    pool_out_index = fm_idx(ph, pw, pc, 12, 16);
                    pool2[pool_out_index] <= pool_max;

                    if (pc == 15) begin
                        pc <= 0;

                        if (pw == 11) begin
                            pw <= 0;

                            if (ph == 11) begin
                                ph <= 0;

                                oh <= 0;
                                ow <= 0;
                                oc <= 0;
                                ic <= 0;
                                kh <= 0;
                                kw <= 0;

                                state <= S_CONV3_INIT;

                                $display("FSM pool2 done");
                            end else begin
                                ph <= ph + 1;
                            end
                        end else begin
                            pw <= pw + 1;
                        end
                    end else begin
                        pc <= pc + 1;
                    end
                end

                // =================================================
                // Conv3 + ReLU + BN
                // Input: 12x12x16
                // Output: 12x12x32
                // =================================================

                S_CONV3_INIT: begin
                    sum <= conv3_b[oc];

                    kh <= 0;
                    kw <= 0;
                    ic <= 0;

                    state <= S_CONV3_MAC;
                end

                S_CONV3_MAC: begin
                    ih = oh + kh - 1;
                    iw = ow + kw - 1;

                    if ((ih >= 0) && (ih < 12) && (iw >= 0) && (iw < 12)) begin
                        in_index = fm_idx(ih, iw, ic, 12, 16);
                        w_index = conv_w_idx(kh, kw, ic, oc, 16, 32);

                        sum <= sum + $signed(pool2[in_index]) * $signed(conv3_w[w_index]);
                    end

                    if (ic == 15) begin
                        ic <= 0;

                        if (kw == 2) begin
                            kw <= 0;

                            if (kh == 2) begin
                                kh <= 0;
                                state <= S_CONV3_SAVE;
                            end else begin
                                kh <= kh + 1;
                            end
                        end else begin
                            kw <= kw + 1;
                        end
                    end else begin
                        ic <= ic + 1;
                    end
                end

                S_CONV3_SAVE: begin
                    if (sum < 0)
                        relu_sum = 0;
                    else
                        relu_sum = sum;

                    bn_mult = relu_sum * $signed(bn3_mul[oc]);
                    out_index = fm_idx(oh, ow, oc, 12, 32);

                    fm3[out_index] <= (bn_mult >>> BN_SHIFT) + $signed(bn3_add[oc]);

                    if (oc == 31) begin
                        oc <= 0;

                        if (ow == 11) begin
                            ow <= 0;

                            if (oh == 11) begin
                                oh <= 0;

                                ph <= 0;
                                pw <= 0;
                                pc <= 0;

                                state <= S_POOL3;

                                $display("FSM conv3_bn done");
                            end else begin
                                oh <= oh + 1;
                                state <= S_CONV3_INIT;
                            end
                        end else begin
                            ow <= ow + 1;
                            state <= S_CONV3_INIT;
                        end
                    end else begin
                        oc <= oc + 1;
                        state <= S_CONV3_INIT;
                    end
                end

                // =================================================
                // Pool3
                // 12x12x32 -> 6x6x32
                // =================================================

                S_POOL3: begin
                    p_ih = ph * 2;
                    p_iw = pw * 2;

                    idx0 = fm_idx(p_ih,     p_iw,     pc, 12, 32);
                    idx1 = fm_idx(p_ih,     p_iw + 1, pc, 12, 32);
                    idx2 = fm_idx(p_ih + 1, p_iw,     pc, 12, 32);
                    idx3 = fm_idx(p_ih + 1, p_iw + 1, pc, 12, 32);

                    pool_max = fm3[idx0];
                    if (fm3[idx1] > pool_max) pool_max = fm3[idx1];
                    if (fm3[idx2] > pool_max) pool_max = fm3[idx2];
                    if (fm3[idx3] > pool_max) pool_max = fm3[idx3];

                    pool_out_index = fm_idx(ph, pw, pc, 6, 32);
                    pool3[pool_out_index] <= pool_max;

                    if (pc == 31) begin
                        pc <= 0;

                        if (pw == 5) begin
                            pw <= 0;

                            if (ph == 5) begin
                                ph <= 0;

                                dense_o <= 0;
                                dense_i <= 0;

                                state <= S_DENSE1_INIT;

                                $display("FSM pool3 done");
                            end else begin
                                ph <= ph + 1;
                            end
                        end else begin
                            pw <= pw + 1;
                        end
                    end else begin
                        pc <= pc + 1;
                    end
                end

                // =================================================
                // Dense1
                // 1152 -> 64, ReLU
                // =================================================

                S_DENSE1_INIT: begin
                    sum <= dense1_b[dense_o];
                    dense_i <= 0;

                    state <= S_DENSE1_MAC;
                end

                S_DENSE1_MAC: begin
                    w_index = dense_w_idx(dense_i, dense_o, 64);

                    sum <= sum + $signed(pool3[dense_i]) * $signed(dense1_w[w_index]);

                    if (dense_i == 1151) begin
                        dense_i <= 0;
                        state <= S_DENSE1_SAVE;
                    end else begin
                        dense_i <= dense_i + 1;
                    end
                end

                S_DENSE1_SAVE: begin
                    if (sum < 0)
                        dense1_out[dense_o] <= 0;
                    else
                        dense1_out[dense_o] <= sum;

                    if (dense_o == 63) begin
                        dense_o <= 0;
                        dense_i <= 0;

                        state <= S_DENSE2_INIT;

                        $display("FSM dense1 done");
                    end else begin
                        dense_o <= dense_o + 1;
                        state <= S_DENSE1_INIT;
                    end
                end

                // =================================================
                // Dense2
                // 64 -> 9, no softmax
                // =================================================

                S_DENSE2_INIT: begin
                    sum <= dense2_b[dense_o];
                    dense_i <= 0;

                    state <= S_DENSE2_MAC;
                end

                S_DENSE2_MAC: begin
                    w_index = dense_w_idx(dense_i, dense_o, 9);

                    sum <= sum + $signed(dense1_out[dense_i]) * $signed(dense2_w[w_index]);

                    if (dense_i == 63) begin
                        dense_i <= 0;
                        state <= S_DENSE2_SAVE;
                    end else begin
                        dense_i <= dense_i + 1;
                    end
                end

                S_DENSE2_SAVE: begin
                    dense2_out[dense_o] <= sum;

                    if (dense_o == 8) begin
                        dense_o <= 0;

                        state <= S_ARGMAX_INIT;

                        $display("FSM dense2 done");
                    end else begin
                        dense_o <= dense_o + 1;
                        state <= S_DENSE2_INIT;
                    end
                end

                // =================================================
                // Argmax
                // =================================================

                S_ARGMAX_INIT: begin
                    max_val <= dense2_out[0];
                    class_idx <= 0;
                    arg_i <= 1;

                    state <= S_ARGMAX_SCAN;
                end

                S_ARGMAX_SCAN: begin
                    if (dense2_out[arg_i] > max_val) begin
                        max_val <= dense2_out[arg_i];
                        class_idx <= arg_i[3:0];
                    end

                    if (arg_i == 8) begin
                        state <= S_DONE;
                    end else begin
                        arg_i <= arg_i + 1;
                    end
                end

                S_DONE: begin
                    done <= 1;
                    busy <= 0;

                    $display("FSM CNN done. class_idx = %0d", class_idx);

                    state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end

            endcase
        end
    end

endmodule