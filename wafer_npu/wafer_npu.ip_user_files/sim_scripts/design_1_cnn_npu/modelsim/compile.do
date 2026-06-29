vlib modelsim_lib/work
vlib modelsim_lib/msim

vlib modelsim_lib/msim/xilinx_vip
vlib modelsim_lib/msim/xpm
vlib modelsim_lib/msim/axi_infrastructure_v1_1_0
vlib modelsim_lib/msim/axi_vip_v1_1_19
vlib modelsim_lib/msim/processing_system7_vip_v1_0_21
vlib modelsim_lib/msim/xil_defaultlib
vlib modelsim_lib/msim/lib_cdc_v1_0_3
vlib modelsim_lib/msim/proc_sys_reset_v5_0_16
vlib modelsim_lib/msim/generic_baseblocks_v2_1_2
vlib modelsim_lib/msim/axi_register_slice_v2_1_33
vlib modelsim_lib/msim/fifo_generator_v13_2_11
vlib modelsim_lib/msim/axi_data_fifo_v2_1_32
vlib modelsim_lib/msim/axi_crossbar_v2_1_34
vlib modelsim_lib/msim/axi_protocol_converter_v2_1_33

vmap xilinx_vip modelsim_lib/msim/xilinx_vip
vmap xpm modelsim_lib/msim/xpm
vmap axi_infrastructure_v1_1_0 modelsim_lib/msim/axi_infrastructure_v1_1_0
vmap axi_vip_v1_1_19 modelsim_lib/msim/axi_vip_v1_1_19
vmap processing_system7_vip_v1_0_21 modelsim_lib/msim/processing_system7_vip_v1_0_21
vmap xil_defaultlib modelsim_lib/msim/xil_defaultlib
vmap lib_cdc_v1_0_3 modelsim_lib/msim/lib_cdc_v1_0_3
vmap proc_sys_reset_v5_0_16 modelsim_lib/msim/proc_sys_reset_v5_0_16
vmap generic_baseblocks_v2_1_2 modelsim_lib/msim/generic_baseblocks_v2_1_2
vmap axi_register_slice_v2_1_33 modelsim_lib/msim/axi_register_slice_v2_1_33
vmap fifo_generator_v13_2_11 modelsim_lib/msim/fifo_generator_v13_2_11
vmap axi_data_fifo_v2_1_32 modelsim_lib/msim/axi_data_fifo_v2_1_32
vmap axi_crossbar_v2_1_34 modelsim_lib/msim/axi_crossbar_v2_1_34
vmap axi_protocol_converter_v2_1_33 modelsim_lib/msim/axi_protocol_converter_v2_1_33

vlog -work xilinx_vip -64 -incr -mfcu  -sv -L axi_vip_v1_1_19 -L processing_system7_vip_v1_0_21 -L xilinx_vip "+incdir+/opt/Xilinx/Vivado/2024.2/data/xilinx_vip/include" \
"/opt/Xilinx/Vivado/2024.2/data/xilinx_vip/hdl/axi4stream_vip_axi4streampc.sv" \
"/opt/Xilinx/Vivado/2024.2/data/xilinx_vip/hdl/axi_vip_axi4pc.sv" \
"/opt/Xilinx/Vivado/2024.2/data/xilinx_vip/hdl/xil_common_vip_pkg.sv" \
"/opt/Xilinx/Vivado/2024.2/data/xilinx_vip/hdl/axi4stream_vip_pkg.sv" \
"/opt/Xilinx/Vivado/2024.2/data/xilinx_vip/hdl/axi_vip_pkg.sv" \
"/opt/Xilinx/Vivado/2024.2/data/xilinx_vip/hdl/axi4stream_vip_if.sv" \
"/opt/Xilinx/Vivado/2024.2/data/xilinx_vip/hdl/axi_vip_if.sv" \
"/opt/Xilinx/Vivado/2024.2/data/xilinx_vip/hdl/clk_vip_if.sv" \
"/opt/Xilinx/Vivado/2024.2/data/xilinx_vip/hdl/rst_vip_if.sv" \

vlog -work xpm -64 -incr -mfcu  -sv -L axi_vip_v1_1_19 -L processing_system7_vip_v1_0_21 -L xilinx_vip "+incdir+../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/ec67/hdl" "+incdir+../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/86fe/hdl" "+incdir+/opt/Xilinx/Vivado/2024.2/data/xilinx_vip/include" \
"/opt/Xilinx/Vivado/2024.2/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
"/opt/Xilinx/Vivado/2024.2/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \

vcom -work xpm -64 -93  \
"/opt/Xilinx/Vivado/2024.2/data/ip/xpm/xpm_VCOMP.vhd" \

vlog -work axi_infrastructure_v1_1_0 -64 -incr -mfcu  "+incdir+../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/ec67/hdl" "+incdir+../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/86fe/hdl" "+incdir+/opt/Xilinx/Vivado/2024.2/data/xilinx_vip/include" \
"../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/ec67/hdl/axi_infrastructure_v1_1_vl_rfs.v" \

vlog -work axi_vip_v1_1_19 -64 -incr -mfcu  -sv -L axi_vip_v1_1_19 -L processing_system7_vip_v1_0_21 -L xilinx_vip "+incdir+../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/ec67/hdl" "+incdir+../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/86fe/hdl" "+incdir+/opt/Xilinx/Vivado/2024.2/data/xilinx_vip/include" \
"../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/8c45/hdl/axi_vip_v1_1_vl_rfs.sv" \

vlog -work processing_system7_vip_v1_0_21 -64 -incr -mfcu  -sv -L axi_vip_v1_1_19 -L processing_system7_vip_v1_0_21 -L xilinx_vip "+incdir+../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/ec67/hdl" "+incdir+../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/86fe/hdl" "+incdir+/opt/Xilinx/Vivado/2024.2/data/xilinx_vip/include" \
"../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/86fe/hdl/processing_system7_vip_v1_0_vl_rfs.sv" \

vlog -work xil_defaultlib -64 -incr -mfcu  "+incdir+../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/ec67/hdl" "+incdir+../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/86fe/hdl" "+incdir+/opt/Xilinx/Vivado/2024.2/data/xilinx_vip/include" \
"../../../bd/design_1_cnn_npu/ip/design_1_cnn_npu_processing_system7_0_0/sim/design_1_cnn_npu_processing_system7_0_0.v" \

vcom -work lib_cdc_v1_0_3 -64 -93  \
"../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/2a4f/hdl/lib_cdc_v1_0_rfs.vhd" \

vcom -work proc_sys_reset_v5_0_16 -64 -93  \
"../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/0831/hdl/proc_sys_reset_v5_0_vh_rfs.vhd" \

vcom -work xil_defaultlib -64 -93  \
"../../../bd/design_1_cnn_npu/ip/design_1_cnn_npu_proc_sys_reset_0_1/sim/design_1_cnn_npu_proc_sys_reset_0_1.vhd" \

vlog -work generic_baseblocks_v2_1_2 -64 -incr -mfcu  "+incdir+../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/ec67/hdl" "+incdir+../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/86fe/hdl" "+incdir+/opt/Xilinx/Vivado/2024.2/data/xilinx_vip/include" \
"../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/0c28/hdl/generic_baseblocks_v2_1_vl_rfs.v" \

vlog -work axi_register_slice_v2_1_33 -64 -incr -mfcu  "+incdir+../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/ec67/hdl" "+incdir+../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/86fe/hdl" "+incdir+/opt/Xilinx/Vivado/2024.2/data/xilinx_vip/include" \
"../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/3ee4/hdl/axi_register_slice_v2_1_vl_rfs.v" \

vlog -work fifo_generator_v13_2_11 -64 -incr -mfcu  "+incdir+../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/ec67/hdl" "+incdir+../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/86fe/hdl" "+incdir+/opt/Xilinx/Vivado/2024.2/data/xilinx_vip/include" \
"../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/6080/simulation/fifo_generator_vlog_beh.v" \

vcom -work fifo_generator_v13_2_11 -64 -93  \
"../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/6080/hdl/fifo_generator_v13_2_rfs.vhd" \

vlog -work fifo_generator_v13_2_11 -64 -incr -mfcu  "+incdir+../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/ec67/hdl" "+incdir+../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/86fe/hdl" "+incdir+/opt/Xilinx/Vivado/2024.2/data/xilinx_vip/include" \
"../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/6080/hdl/fifo_generator_v13_2_rfs.v" \

vlog -work axi_data_fifo_v2_1_32 -64 -incr -mfcu  "+incdir+../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/ec67/hdl" "+incdir+../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/86fe/hdl" "+incdir+/opt/Xilinx/Vivado/2024.2/data/xilinx_vip/include" \
"../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/65ce/hdl/axi_data_fifo_v2_1_vl_rfs.v" \

vlog -work axi_crossbar_v2_1_34 -64 -incr -mfcu  "+incdir+../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/ec67/hdl" "+incdir+../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/86fe/hdl" "+incdir+/opt/Xilinx/Vivado/2024.2/data/xilinx_vip/include" \
"../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/a7e3/hdl/axi_crossbar_v2_1_vl_rfs.v" \

vlog -work xil_defaultlib -64 -incr -mfcu  "+incdir+../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/ec67/hdl" "+incdir+../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/86fe/hdl" "+incdir+/opt/Xilinx/Vivado/2024.2/data/xilinx_vip/include" \
"../../../bd/design_1_cnn_npu/ip/design_1_cnn_npu_axi_interconnect_0_imp_xbar_0/sim/design_1_cnn_npu_axi_interconnect_0_imp_xbar_0.v" \
"../../../bd/design_1_cnn_npu/ipshared/48ff/hdl/myip_cnn_classification_slave_lite_v1_0_S00_AXI.v" \
"../../../bd/design_1_cnn_npu/ipshared/48ff/src/cnn_fsm_v2.v" \
"../../../bd/design_1_cnn_npu/ipshared/48ff/hdl/myip_cnn_classification.v" \
"../../../bd/design_1_cnn_npu/ip/design_1_cnn_npu_myip_cnn_classificat_0_0/sim/design_1_cnn_npu_myip_cnn_classificat_0_0.v" \
"../../../bd/design_1_cnn_npu/ipshared/bab1/hdl/myip_cnn_uart_cntr_slave_lite_v1_0_S00_AXI.v" \
"../../../bd/design_1_cnn_npu/ipshared/bab1/hdl/myip_cnn_uart_cntr.v" \
"../../../bd/design_1_cnn_npu/ip/design_1_cnn_npu_myip_cnn_uart_cntr_0_0/sim/design_1_cnn_npu_myip_cnn_uart_cntr_0_0.v" \
"../../../bd/design_1_cnn_npu/ipshared/5dfa/hdl/myip_uart_rxtx_slave_lite_v1_0_S00_AXI.v" \
"../../../bd/design_1_cnn_npu/ipshared/5dfa/src/uart_rxtx.v" \
"../../../bd/design_1_cnn_npu/ipshared/5dfa/hdl/myip_uart_rxtx.v" \
"../../../bd/design_1_cnn_npu/ip/design_1_cnn_npu_myip_uart_rxtx_0_0/sim/design_1_cnn_npu_myip_uart_rxtx_0_0.v" \

vlog -work axi_protocol_converter_v2_1_33 -64 -incr -mfcu  "+incdir+../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/ec67/hdl" "+incdir+../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/86fe/hdl" "+incdir+/opt/Xilinx/Vivado/2024.2/data/xilinx_vip/include" \
"../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/27ae/hdl/axi_protocol_converter_v2_1_vl_rfs.v" \

vlog -work xil_defaultlib -64 -incr -mfcu  "+incdir+../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/ec67/hdl" "+incdir+../../../../wafer_npu.gen/sources_1/bd/design_1_cnn_npu/ipshared/86fe/hdl" "+incdir+/opt/Xilinx/Vivado/2024.2/data/xilinx_vip/include" \
"../../../bd/design_1_cnn_npu/ip/design_1_cnn_npu_axi_interconnect_0_imp_auto_pc_0/sim/design_1_cnn_npu_axi_interconnect_0_imp_auto_pc_0.v" \
"../../../bd/design_1_cnn_npu/sim/design_1_cnn_npu.v" \

vlog -work xil_defaultlib \
"glbl.v"

