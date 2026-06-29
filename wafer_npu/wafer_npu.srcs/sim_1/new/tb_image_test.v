`timescale 1ns / 1ps

module tb_test_top;

    reg clk;
    reg reset_p;
    reg start;

    wire done;
    wire busy;
    wire [3:0] class_idx;

    reg img_we;
    reg [11:0] img_addr;
    reg signed [15:0] img_wdata;

    test_top dut (
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
            $display("Loading image to TB memory: %s", image_path);

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

            $display("Image write done.");
            $display("tb_img_mem[0] = %0d", tb_img_mem[0]);
            $display("tb_img_mem[1] = %0d", tb_img_mem[1]);
            $display("tb_img_mem[2] = %0d", tb_img_mem[2]);
        end
    endtask

    task run_one_case;
        input integer case_id;
        input integer true_idx;
        input integer expected_idx;
        input [8*64-1:0] class_name;
        input [8*256-1:0] image_path;
        input integer result_f;

        integer pass;
        begin
            $display("");
            $display("======================================");
            $display("CASE %0d", case_id);
            $display("class_name   = %s", class_name);
            $display("true_idx     = %0d", true_idx);
            $display("expected_idx = %0d", expected_idx);
            $display("image_path   = %s", image_path);
            $display("======================================");

            reset_p = 1;
            start = 0;
            img_we = 0;
            img_addr = 0;
            img_wdata = 0;

            repeat (5) @(posedge clk);

            reset_p = 0;

            repeat (5) @(posedge clk);

            write_image_to_dut(image_path);

            start = 1;
            @(posedge clk);
            start = 0;

            wait(done == 1'b1);
            @(posedge clk);

            if (class_idx == expected_idx)
                pass = 1;
            else
                pass = 0;

            $display("RESULT: pred=%0d, expected=%0d, pass=%0d",
                     class_idx, expected_idx, pass);

            $fwrite(result_f,
                "%0d,%0d,%0d,%0d,%s,%s,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",
                case_id,
                true_idx,
                expected_idx,
                class_idx,
                class_name,
                image_path,
                pass,
                dut.dense2_out[0],
                dut.dense2_out[1],
                dut.dense2_out[2],
                dut.dense2_out[3],
                dut.dense2_out[4],
                dut.dense2_out[5],
                dut.dense2_out[6],
                dut.dense2_out[7],
                dut.dense2_out[8]
            );
        end
    endtask

    integer list_f;
    integer result_f;
    integer scan_ret;

    integer case_id;
    integer true_idx;
    integer expected_idx;

    reg [8*64-1:0] class_name;
    reg [8*256-1:0] image_path;

    integer total_count;
    integer pass_count;

    initial begin
        reset_p = 1;
        start = 0;
        img_we = 0;
        img_addr = 0;
        img_wdata = 0;

        total_count = 0;
        pass_count = 0;

        repeat (10) @(posedge clk);

        list_f = $fopen("/home/ming/workspace_ondevice_2/Project_NPU/mem/test_list.txt", "r");

        if (list_f == 0) begin
            $display("ERROR: test_list open failed.");
            $finish;
        end

        result_f = $fopen("/home/ming/workspace_ondevice_2/Project_NPU/vivado_batch_result.csv", "w");

        if (result_f == 0) begin
            $display("ERROR: result csv open failed.");
            $finish;
        end

        $fwrite(result_f,
            "case_id,true_idx,expected_idx,pred_idx,class_name,image_path,pass,dense0,dense1,dense2,dense3,dense4,dense5,dense6,dense7,dense8\n"
        );

        while (!$feof(list_f)) begin
            scan_ret = $fscanf(
                list_f,
                "%d %d %d %s %s\n",
                case_id,
                true_idx,
                expected_idx,
                class_name,
                image_path
            );

            if (scan_ret == 5) begin
                run_one_case(
                    case_id,
                    true_idx,
                    expected_idx,
                    class_name,
                    image_path,
                    result_f
                );

                total_count = total_count + 1;

                if (class_idx == expected_idx)
                    pass_count = pass_count + 1;
            end
        end

        $fclose(list_f);
        $fclose(result_f);

        $display("");
        $display("======================================");
        $display("BATCH TEST DONE");
        $display("total = %0d", total_count);
        $display("pass  = %0d", pass_count);
        $display("fail  = %0d", total_count - pass_count);
        $display("result csv = C:/project_2/mem/vivado_batch_result.csv");
        $display("======================================");

        $finish;
    end

endmodule