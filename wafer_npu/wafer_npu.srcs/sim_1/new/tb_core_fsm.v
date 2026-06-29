`timescale 1ns / 1ps

module tb_cnn_core_fsm;

    reg clk;
    reg reset_p;
    reg start;

    wire done;
    wire busy;
    wire [3:0] class_idx;

    reg img_we;
    reg [11:0] img_addr;
    reg signed [15:0] img_wdata;

    cnn_core_fsm dut (
        .clk(clk),
        .reset_p(reset_p),

        .start(start),
        .done(done),
        .busy(busy),
        .class_idx(class_idx),

        .img_we(img_we),
        .img_addr(img_addr),
        .img_wdata(img_wdata)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    reg signed [15:0] tb_img_mem [0:2304-1];

    task write_image_to_dut;
        input [8*256-1:0] image_path;

        integer i;
        begin
            $display("Loading image: %s", image_path);

            $readmemh(image_path, tb_img_mem);

            img_we = 0;
            img_addr = 0;
            img_wdata = 0;

            @(posedge clk);

            for (i = 0; i < 2304; i = i + 1) begin
                img_addr = i[11:0];
                img_wdata = tb_img_mem[i];
                img_we = 1;
                @(posedge clk);
            end

            img_we = 0;
            img_addr = 0;
            img_wdata = 0;

            @(posedge clk);

            $display("Image write done");
            $display("img[0] = %0d", tb_img_mem[0]);
            $display("img[1] = %0d", tb_img_mem[1]);
            $display("img[2] = %0d", tb_img_mem[2]);
        end
    endtask

    task dump_all_layers;
        integer f;
        integer i;
        begin
            f = $fopen("/home/ming/workspace_ondevice_2/Project_NPU/mem/fsm_fm1_out.txt", "w");
            for (i = 0; i < 48*48*8; i = i + 1) $fwrite(f, "%0d\n", dut.fm1[i]);
            $fclose(f);

            f = $fopen("/home/ming/workspace_ondevice_2/Project_NPU/mem/fsm_pool1_out.txt", "w");
            for (i = 0; i < 24*24*8; i = i + 1) $fwrite(f, "%0d\n", dut.pool1[i]);
            $fclose(f);

            f = $fopen("/home/ming/workspace_ondevice_2/Project_NPU/mem/fsm_fm2_out.txt", "w");
            for (i = 0; i < 24*24*16; i = i + 1) $fwrite(f, "%0d\n", dut.fm2[i]);
            $fclose(f);

            f = $fopen("/home/ming/workspace_ondevice_2/Project_NPU/mem/fsm_pool2_out.txt", "w");
            for (i = 0; i < 12*12*16; i = i + 1) $fwrite(f, "%0d\n", dut.pool2[i]);
            $fclose(f);

            f = $fopen("/home/ming/workspace_ondevice_2/Project_NPU/mem/fsm_fm3_out.txt", "w");
            for (i = 0; i < 12*12*32; i = i + 1) $fwrite(f, "%0d\n", dut.fm3[i]);
            $fclose(f);

            f = $fopen("/home/ming/workspace_ondevice_2/Project_NPU/mem/fsm_pool3_out.txt", "w");
            for (i = 0; i < 6*6*32; i = i + 1) $fwrite(f, "%0d\n", dut.pool3[i]);
            $fclose(f);

            f = $fopen("/home/ming/workspace_ondevice_2/Project_NPU/mem/fsm_dense1_out.txt", "w");
            for (i = 0; i < 64; i = i + 1) $fwrite(f, "%0d\n", dut.dense1_out[i]);
            $fclose(f);

            f = $fopen("/home/ming/workspace_ondevice_2/Project_NPU/mem/fsm_dense2_out.txt", "w");
            for (i = 0; i < 9; i = i + 1) $fwrite(f, "%0d\n", dut.dense2_out[i]);
            $fclose(f);

            $display("All FSM layer outputs dumped.");
        end
    endtask

    initial begin
        reset_p = 1;
        start = 0;

        img_we = 0;
        img_addr = 0;
        img_wdata = 0;

        repeat (10) @(posedge clk);

        reset_p = 0;

        repeat (10) @(posedge clk);

        write_image_to_dut(
            "/home/ming/workspace_ondevice_2/Project_NPU/mem/input_images_by_class/0_Center/input_0_Center_0_idx11.mem"
        );

        repeat (10) @(posedge clk);

        start = 1;
        @(posedge clk);
        start = 0;

        wait(done == 1'b1);

        repeat (10) @(posedge clk);

        dump_all_layers();

        $display("======================================");
        $display("FSM TEST DONE");
        $display("class_idx = %0d", class_idx);
        $display("======================================");

        $finish;
    end

endmodule