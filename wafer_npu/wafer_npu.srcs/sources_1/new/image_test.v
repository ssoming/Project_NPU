`timescale 1ns / 1ps

module test_top(
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

    // ============================================================
    // Model parameter memory
    // ============================================================

    // Conv1: 3x3x1x8 = 72
    reg signed [7:0]  conv1_w [0:72-1];
    reg signed [63:0] conv1_b [0:8-1];
    reg signed [31:0] bn1_mul [0:8-1];
    reg signed [31:0] bn1_add [0:8-1];

    // Conv2: 3x3x8x16 = 1152
    reg signed [7:0]  conv2_w [0:1152-1];
    reg signed [63:0] conv2_b [0:16-1];
    reg signed [31:0] bn2_mul [0:16-1];
    reg signed [31:0] bn2_add [0:16-1];

    // Conv3: 3x3x16x32 = 4608
    reg signed [7:0]  conv3_w [0:4608-1];
    reg signed [63:0] conv3_b [0:32-1];
    reg signed [31:0] bn3_mul [0:32-1];
    reg signed [31:0] bn3_add [0:32-1];

    // Dense1: 1152 x 64
    reg signed [7:0]  dense1_w [0:73728-1];
    reg signed [63:0] dense1_b [0:64-1];

    // Dense2: 64 x 9
    reg signed [7:0]  dense2_w [0:576-1];
    reg signed [63:0] dense2_b [0:9-1];

    // ============================================================
    // Feature map memory
    // ============================================================

    // Input image: 48x48x1, value: 0, 64, 128
    reg signed [15:0] img_mem [0:48*48-1];

    always @(posedge clk) begin
        if (img_we && !busy) begin
            img_mem[img_addr] <= img_wdata;
        end
    end

    // After conv1+BN: 48x48x8, scale=128
    reg signed [31:0] fm1 [0:48*48*8-1];

    // After pool1: 24x24x8
    reg signed [31:0] pool1 [0:24*24*8-1];

    // After conv2+BN: 24x24x16
    reg signed [31:0] fm2 [0:24*24*16-1];

    // After pool2: 12x12x16
    reg signed [31:0] pool2 [0:12*12*16-1];

    // After conv3+BN: 12x12x32
    reg signed [31:0] fm3 [0:12*12*32-1];

    // After pool3: 6x6x32 = 1152
    reg signed [31:0] pool3 [0:6*6*32-1];

    // Dense output
    reg signed [63:0] dense1_out [0:64-1];
    reg signed [63:0] dense2_out [0:9-1];


    // ============================================================
    // File load
    // ============================================================

initial begin
    $display("Loading mem files...");

    $readmemh("/home/ming/workspace_ondevice_2/Project_NPU/mem_file/conv1_w.mem", conv1_w);
    $readmemh("/home/ming/workspace_ondevice_2/Project_NPU/mem_file/conv1_b.mem", conv1_b);
    $readmemh("/home/ming/workspace_ondevice_2/Project_NPU/mem_file/bn1_mul.mem", bn1_mul);
    $readmemh("/home/ming/workspace_ondevice_2/Project_NPU/mem_file/bn1_add.mem", bn1_add);

    $readmemh("/home/ming/workspace_ondevice_2/Project_NPU/mem_file/conv2_w.mem", conv2_w);
    $readmemh("/home/ming/workspace_ondevice_2/Project_NPU/mem_file/conv2_b.mem", conv2_b);
    $readmemh("/home/ming/workspace_ondevice_2/Project_NPU/mem_file/bn2_mul.mem", bn2_mul);
    $readmemh("/home/ming/workspace_ondevice_2/Project_NPU/mem_file/bn2_add.mem", bn2_add);

    $readmemh("/home/ming/workspace_ondevice_2/Project_NPU/mem_file/conv3_w.mem", conv3_w);
    $readmemh("/home/ming/workspace_ondevice_2/Project_NPU/mem_file/conv3_b.mem", conv3_b);
    $readmemh("/home/ming/workspace_ondevice_2/Project_NPU/mem_file/bn3_mul.mem", bn3_mul);
    $readmemh("/home/ming/workspace_ondevice_2/Project_NPU/mem_file/bn3_add.mem", bn3_add);

    $readmemh("/home/ming/workspace_ondevice_2/Project_NPU/mem_file/dense1_w.mem", dense1_w);
    $readmemh("/home/ming/workspace_ondevice_2/Project_NPU/mem_file/dense1_b.mem", dense1_b);

    $readmemh("/home/ming/workspace_ondevice_2/Project_NPU/mem_file/dense2_w.mem", dense2_w);
    $readmemh("/home/ming/workspace_ondevice_2/Project_NPU/mem_file/dense2_b.mem", dense2_b);

 //   $readmemh("C:/project_2/mem/input_image.mem", img_mem);

    $display("Mem file load done.");
end

    // ============================================================
    // Index functions
    // ============================================================

    function automatic integer fm_idx;
        input integer h;
        input integer w;
        input integer c;
        input integer width;
        input integer channels;
        begin
            fm_idx = (h * width + w) * channels + c;
        end
    endfunction

    function automatic integer conv_w_idx;
        input integer kh;
        input integer kw;
        input integer ic;
        input integer oc;
        input integer cin;
        input integer cout;
        begin
            // Python 저장 순서: kh -> kw -> input_channel -> output_channel
            conv_w_idx = (((kh * 3 + kw) * cin + ic) * cout + oc);
        end
    endfunction

    function automatic integer dense_w_idx;
        input integer in_i;
        input integer out_i;
        input integer out_dim;
        begin
            // Python 저장 순서: input index -> output index
            dense_w_idx = in_i * out_dim + out_i;
        end
    endfunction

    // ============================================================
    // Main control for simulation
    // ============================================================

    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin
            done <= 0;
            busy <= 0;
            class_idx <= 0;
        end else begin
            if (start && !busy) begin
                busy <= 1;
                done <= 0;

                run_all();

                done <= 1;
                busy <= 0;
            end
        end
    end

    // ============================================================
    // Full CNN
    // ============================================================

    task automatic run_all;
        begin
            $display("CNN start");

            conv1_bn();
            $display("conv1_bn done");

            maxpool1();
            $display("pool1 done");

            conv2_bn();
            $display("conv2_bn done");

            maxpool2();
            $display("pool2 done");

            conv3_bn();
            $display("conv3_bn done");

            maxpool3();
            $display("pool3 done");

            dense1();
            $display("dense1 done");

            dense2();
            $display("dense2 done");

            argmax9();
            $display("argmax done. class_idx = %0d", class_idx);
            
            dump_all_layers_ref();
        end
    endtask

    // ============================================================
    // Conv1 + ReLU + BN
    // Input: 48x48x1, scale=128
    // Conv output scale = 128 * 64 = 8192
    // BN output scale = 128
    // ============================================================

    task automatic conv1_bn;
        integer oh, ow, oc, kh, kw;
        integer ih, iw;
        integer in_index, w_index, out_index;
        reg signed [63:0] sum;
        reg signed [63:0] relu_sum;
        reg signed [95:0] bn_mult;
        begin
            for (oh = 0; oh < 48; oh = oh + 1) begin
                for (ow = 0; ow < 48; ow = ow + 1) begin
                    for (oc = 0; oc < 8; oc = oc + 1) begin
                        sum = conv1_b[oc];

                        for (kh = 0; kh < 3; kh = kh + 1) begin
                            for (kw = 0; kw < 3; kw = kw + 1) begin
                                ih = oh + kh - 1;
                                iw = ow + kw - 1;

                                if (ih >= 0 && ih < 48 && iw >= 0 && iw < 48) begin
                                    in_index = ih * 48 + iw;
                                    w_index = conv_w_idx(kh, kw, 0, oc, 1, 8);

                                    sum = sum + $signed(img_mem[in_index]) * $signed(conv1_w[w_index]);
                                end
                            end
                        end

                        if (sum < 0)
                            relu_sum = 0;
                        else
                            relu_sum = sum;

                        bn_mult = relu_sum * $signed(bn1_mul[oc]);
                        out_index = fm_idx(oh, ow, oc, 48, 8);

                        fm1[out_index] = (bn_mult >>> BN_SHIFT) + $signed(bn1_add[oc]);
                    end
                end
            end
        end
    endtask

    // ============================================================
    // MaxPool1: 48x48x8 -> 24x24x8
    // ============================================================

    task automatic maxpool1;
        integer oh, ow, c;
        integer ih, iw;
        integer idx0, idx1, idx2, idx3, out_index;
        reg signed [31:0] m;
        begin
            for (oh = 0; oh < 24; oh = oh + 1) begin
                for (ow = 0; ow < 24; ow = ow + 1) begin
                    for (c = 0; c < 8; c = c + 1) begin
                        ih = oh * 2;
                        iw = ow * 2;

                        idx0 = fm_idx(ih,     iw,     c, 48, 8);
                        idx1 = fm_idx(ih,     iw + 1, c, 48, 8);
                        idx2 = fm_idx(ih + 1, iw,     c, 48, 8);
                        idx3 = fm_idx(ih + 1, iw + 1, c, 48, 8);

                        m = fm1[idx0];
                        if (fm1[idx1] > m) m = fm1[idx1];
                        if (fm1[idx2] > m) m = fm1[idx2];
                        if (fm1[idx3] > m) m = fm1[idx3];

                        out_index = fm_idx(oh, ow, c, 24, 8);
                        pool1[out_index] = m;
                    end
                end
            end
        end
    endtask

    // ============================================================
    // Conv2 + ReLU + BN
    // Input: 24x24x8, scale=128
    // Output: 24x24x16, scale=128 after BN
    // ============================================================

    task automatic conv2_bn;
        integer oh, ow, oc, kh, kw, ic;
        integer ih, iw;
        integer in_index, w_index, out_index;
        reg signed [63:0] sum;
        reg signed [63:0] relu_sum;
        reg signed [95:0] bn_mult;
        begin
            for (oh = 0; oh < 24; oh = oh + 1) begin
                for (ow = 0; ow < 24; ow = ow + 1) begin
                    for (oc = 0; oc < 16; oc = oc + 1) begin
                        sum = conv2_b[oc];

                        for (kh = 0; kh < 3; kh = kh + 1) begin
                            for (kw = 0; kw < 3; kw = kw + 1) begin
                                ih = oh + kh - 1;
                                iw = ow + kw - 1;

                                if (ih >= 0 && ih < 24 && iw >= 0 && iw < 24) begin
                                    for (ic = 0; ic < 8; ic = ic + 1) begin
                                        in_index = fm_idx(ih, iw, ic, 24, 8);
                                        w_index = conv_w_idx(kh, kw, ic, oc, 8, 16);

                                        sum = sum + $signed(pool1[in_index]) * $signed(conv2_w[w_index]);
                                    end
                                end
                            end
                        end

                        if (sum < 0)
                            relu_sum = 0;
                        else
                            relu_sum = sum;

                        bn_mult = relu_sum * $signed(bn2_mul[oc]);
                        out_index = fm_idx(oh, ow, oc, 24, 16);

                        fm2[out_index] = (bn_mult >>> BN_SHIFT) + $signed(bn2_add[oc]);
                    end
                end
            end
        end
    endtask

    // ============================================================
    // MaxPool2: 24x24x16 -> 12x12x16
    // ============================================================

    task automatic maxpool2;
        integer oh, ow, c;
        integer ih, iw;
        integer idx0, idx1, idx2, idx3, out_index;
        reg signed [31:0] m;
        begin
            for (oh = 0; oh < 12; oh = oh + 1) begin
                for (ow = 0; ow < 12; ow = ow + 1) begin
                    for (c = 0; c < 16; c = c + 1) begin
                        ih = oh * 2;
                        iw = ow * 2;

                        idx0 = fm_idx(ih,     iw,     c, 24, 16);
                        idx1 = fm_idx(ih,     iw + 1, c, 24, 16);
                        idx2 = fm_idx(ih + 1, iw,     c, 24, 16);
                        idx3 = fm_idx(ih + 1, iw + 1, c, 24, 16);

                        m = fm2[idx0];
                        if (fm2[idx1] > m) m = fm2[idx1];
                        if (fm2[idx2] > m) m = fm2[idx2];
                        if (fm2[idx3] > m) m = fm2[idx3];

                        out_index = fm_idx(oh, ow, c, 12, 16);
                        pool2[out_index] = m;
                    end
                end
            end
        end
    endtask

    // ============================================================
    // Conv3 + ReLU + BN
    // Input: 12x12x16, scale=128
    // Output: 12x12x32, scale=128 after BN
    // ============================================================

    task automatic conv3_bn;
        integer oh, ow, oc, kh, kw, ic;
        integer ih, iw;
        integer in_index, w_index, out_index;
        reg signed [63:0] sum;
        reg signed [63:0] relu_sum;
        reg signed [95:0] bn_mult;
        begin
            for (oh = 0; oh < 12; oh = oh + 1) begin
                for (ow = 0; ow < 12; ow = ow + 1) begin
                    for (oc = 0; oc < 32; oc = oc + 1) begin
                        sum = conv3_b[oc];

                        for (kh = 0; kh < 3; kh = kh + 1) begin
                            for (kw = 0; kw < 3; kw = kw + 1) begin
                                ih = oh + kh - 1;
                                iw = ow + kw - 1;

                                if (ih >= 0 && ih < 12 && iw >= 0 && iw < 12) begin
                                    for (ic = 0; ic < 16; ic = ic + 1) begin
                                        in_index = fm_idx(ih, iw, ic, 12, 16);
                                        w_index = conv_w_idx(kh, kw, ic, oc, 16, 32);

                                        sum = sum + $signed(pool2[in_index]) * $signed(conv3_w[w_index]);
                                    end
                                end
                            end
                        end

                        if (sum < 0)
                            relu_sum = 0;
                        else
                            relu_sum = sum;

                        bn_mult = relu_sum * $signed(bn3_mul[oc]);
                        out_index = fm_idx(oh, ow, oc, 12, 32);

                        fm3[out_index] = (bn_mult >>> BN_SHIFT) + $signed(bn3_add[oc]);
                    end
                end
            end
        end
    endtask

    // ============================================================
    // MaxPool3: 12x12x32 -> 6x6x32
    // ============================================================

    task automatic maxpool3;
        integer oh, ow, c;
        integer ih, iw;
        integer idx0, idx1, idx2, idx3, out_index;
        reg signed [31:0] m;
        begin
            for (oh = 0; oh < 6; oh = oh + 1) begin
                for (ow = 0; ow < 6; ow = ow + 1) begin
                    for (c = 0; c < 32; c = c + 1) begin
                        ih = oh * 2;
                        iw = ow * 2;

                        idx0 = fm_idx(ih,     iw,     c, 12, 32);
                        idx1 = fm_idx(ih,     iw + 1, c, 12, 32);
                        idx2 = fm_idx(ih + 1, iw,     c, 12, 32);
                        idx3 = fm_idx(ih + 1, iw + 1, c, 12, 32);

                        m = fm3[idx0];
                        if (fm3[idx1] > m) m = fm3[idx1];
                        if (fm3[idx2] > m) m = fm3[idx2];
                        if (fm3[idx3] > m) m = fm3[idx3];

                        out_index = fm_idx(oh, ow, c, 6, 32);
                        pool3[out_index] = m;
                    end
                end
            end
        end
    endtask

    // ============================================================
    // Dense1: 1152 -> 64, ReLU
    // Input scale = 128
    // Weight scale = 64
    // Output scale = 8192
    // ============================================================

    task automatic dense1;
        integer o, i, w_index;
        reg signed [63:0] sum;
        begin
            for (o = 0; o < 64; o = o + 1) begin
                sum = dense1_b[o];

                for (i = 0; i < 1152; i = i + 1) begin
                    w_index = dense_w_idx(i, o, 64);
                    sum = sum + $signed(pool3[i]) * $signed(dense1_w[w_index]);
                end

                if (sum < 0)
                    dense1_out[o] = 0;
                else
                    dense1_out[o] = sum;
            end
        end
    endtask

    // ============================================================
    // Dense2: 64 -> 9, no softmax
    // Input scale = 8192
    // Weight scale = 64
    // Output scale = 524288
    // ============================================================

    task automatic dense2;
        integer o, i, w_index;
        reg signed [63:0] sum;
        begin
            for (o = 0; o < 9; o = o + 1) begin
                sum = dense2_b[o];

                for (i = 0; i < 64; i = i + 1) begin
                    w_index = dense_w_idx(i, o, 9);
                    sum = sum + $signed(dense1_out[i]) * $signed(dense2_w[w_index]);
                end

                dense2_out[o] = sum;
            end
        end
    endtask

    // ============================================================
    // Argmax
    // ============================================================

    task automatic argmax9;
        integer i;
        reg signed [63:0] max_val;
        begin
            max_val = dense2_out[0];
            class_idx = 0;

            for (i = 1; i < 9; i = i + 1) begin
                if (dense2_out[i] > max_val) begin
                    max_val = dense2_out[i];
                    class_idx = i[3:0];
                end
            end

            $display("dense2_out:");
            for (i = 0; i < 9; i = i + 1) begin
                $display("  class %0d: %0d", i, dense2_out[i]);
            end

            $display("result class_idx = %0d", class_idx);
        end
    endtask
    
    task dump_all_layers_ref;
        integer f;
        integer i;
        begin
            f = $fopen("/home/ming/workspace_ondevice_2/Project_NPU/mem/ref_fm1_out.txt", "w");
            for (i = 0; i < 48*48*8; i = i + 1) $fwrite(f, "%0d\n", fm1[i]);
            $fclose(f);
    
            f = $fopen("/home/ming/workspace_ondevice_2/Project_NPU/mem/ref_pool1_out.txt", "w");
            for (i = 0; i < 24*24*8; i = i + 1) $fwrite(f, "%0d\n", pool1[i]);
            $fclose(f);
    
            f = $fopen("/home/ming/workspace_ondevice_2/Project_NPU/mem/ref_fm2_out.txt", "w");
            for (i = 0; i < 24*24*16; i = i + 1) $fwrite(f, "%0d\n", fm2[i]);
            $fclose(f);
    
            f = $fopen("/home/ming/workspace_ondevice_2/Project_NPU/mem/ref_pool2_out.txt", "w");
            for (i = 0; i < 12*12*16; i = i + 1) $fwrite(f, "%0d\n", pool2[i]);
            $fclose(f);
    
            f = $fopen("/home/ming/workspace_ondevice_2/Project_NPU/mem/ref_fm3_out.txt", "w");
            for (i = 0; i < 12*12*32; i = i + 1) $fwrite(f, "%0d\n", fm3[i]);
            $fclose(f);
    
            f = $fopen("/home/ming/workspace_ondevice_2/Project_NPU/mem/ref_pool3_out.txt", "w");
            for (i = 0; i < 6*6*32; i = i + 1) $fwrite(f, "%0d\n", pool3[i]);
            $fclose(f);
    
            f = $fopen("/home/ming/workspace_ondevice_2/Project_NPU/mem/ref_dense1_out.txt", "w");
            for (i = 0; i < 64; i = i + 1) $fwrite(f, "%0d\n", dense1_out[i]);
            $fclose(f);
    
            f = $fopen("/home/ming/workspace_ondevice_2/Project_NPU/mem/ref_dense2_out.txt", "w");
            for (i = 0; i < 9; i = i + 1) $fwrite(f, "%0d\n", dense2_out[i]);
            $fclose(f);
    
            $display("Reference layer outputs dumped.");
        end
    endtask

endmodule