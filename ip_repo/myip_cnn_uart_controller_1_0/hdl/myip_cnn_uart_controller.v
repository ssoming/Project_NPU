`timescale 1ns / 1ps
//==============================================================================
// myip_controller.v  - Top wrapper
//==============================================================================
module myip_controller #(
    parameter integer C_S00_AXI_DATA_WIDTH = 32,
    parameter integer IMG_N = 2304,
    parameter integer C_S00_AXI_ADDR_WIDTH = 5
)(
    // Slave AXI (PS → Controller)
    input  wire        s00_axi_aclk,
    input  wire        s00_axi_aresetn,
    input  wire [C_S00_AXI_ADDR_WIDTH-1:0] s00_axi_awaddr,
    input  wire [2:0]  s00_axi_awprot,
    input  wire        s00_axi_awvalid,
    output wire        s00_axi_awready,
    input  wire [C_S00_AXI_DATA_WIDTH-1:0] s00_axi_wdata,
    input  wire [3:0]  s00_axi_wstrb,
    input  wire        s00_axi_wvalid,
    output wire        s00_axi_wready,
    output wire [1:0]  s00_axi_bresp,
    output wire        s00_axi_bvalid,
    input  wire        s00_axi_bready,
    input  wire [C_S00_AXI_ADDR_WIDTH-1:0] s00_axi_araddr,
    input  wire [2:0]  s00_axi_arprot,
    input  wire        s00_axi_arvalid,
    output wire        s00_axi_arready,
    output wire [C_S00_AXI_DATA_WIDTH-1:0] s00_axi_rdata,
    output wire [1:0]  s00_axi_rresp,
    output wire        s00_axi_rvalid,
    input  wire        s00_axi_rready,

    // Master AXI → UART IP
    output wire [31:0] m00_axi_awaddr,
    output wire        m00_axi_awvalid,
    input  wire        m00_axi_awready,
    output wire [31:0] m00_axi_wdata,
    output wire        m00_axi_wvalid,
    input  wire        m00_axi_wready,
    output wire [3:0]  m00_axi_wstrb,
    input  wire [1:0]  m00_axi_bresp,
    input  wire        m00_axi_bvalid,
    output wire        m00_axi_bready,
    output wire [31:0] m00_axi_araddr,
    output wire        m00_axi_arvalid,
    input  wire        m00_axi_arready,
    input  wire [31:0] m00_axi_rdata,
    input  wire [1:0]  m00_axi_rresp,
    input  wire        m00_axi_rvalid,
    output wire        m00_axi_rready,

    // Master AXI → CNN IP
    output wire [31:0] m01_axi_awaddr,
    output wire        m01_axi_awvalid,
    input  wire        m01_axi_awready,
    output wire [31:0] m01_axi_wdata,
    output wire        m01_axi_wvalid,
    input  wire        m01_axi_wready,
    output wire [3:0]  m01_axi_wstrb,
    input  wire [1:0]  m01_axi_bresp,
    input  wire        m01_axi_bvalid,
    output wire        m01_axi_bready,
    output wire [31:0] m01_axi_araddr,
    output wire        m01_axi_arvalid,
    input  wire        m01_axi_arready,
    input  wire [31:0] m01_axi_rdata,
    input  wire [1:0]  m01_axi_rresp,
    input  wire        m01_axi_rvalid,
    output wire        m01_axi_rready
);

    myip_controller_S00_AXI #(
        .C_S_AXI_DATA_WIDTH(C_S00_AXI_DATA_WIDTH),
        .IMG_N(IMG_N),
        .C_S_AXI_ADDR_WIDTH(C_S00_AXI_ADDR_WIDTH)
    ) inst (
        .S_AXI_ACLK    (s00_axi_aclk),
        .S_AXI_ARESETN (s00_axi_aresetn),
        .S_AXI_AWADDR  (s00_axi_awaddr),  .S_AXI_AWPROT(s00_axi_awprot),
        .S_AXI_AWVALID (s00_axi_awvalid), .S_AXI_AWREADY(s00_axi_awready),
        .S_AXI_WDATA   (s00_axi_wdata),   .S_AXI_WSTRB (s00_axi_wstrb),
        .S_AXI_WVALID  (s00_axi_wvalid),  .S_AXI_WREADY(s00_axi_wready),
        .S_AXI_BRESP   (s00_axi_bresp),   .S_AXI_BVALID(s00_axi_bvalid),
        .S_AXI_BREADY  (s00_axi_bready),
        .S_AXI_ARADDR  (s00_axi_araddr),  .S_AXI_ARPROT(s00_axi_arprot),
        .S_AXI_ARVALID (s00_axi_arvalid), .S_AXI_ARREADY(s00_axi_arready),
        .S_AXI_RDATA   (s00_axi_rdata),   .S_AXI_RRESP (s00_axi_rresp),
        .S_AXI_RVALID  (s00_axi_rvalid),  .S_AXI_RREADY(s00_axi_rready),

        .m_uart_awaddr (m00_axi_awaddr),  .m_uart_awvalid(m00_axi_awvalid),
        .m_uart_awready(m00_axi_awready),
        .m_uart_wdata  (m00_axi_wdata),   .m_uart_wvalid (m00_axi_wvalid),
        .m_uart_wready (m00_axi_wready),  .m_uart_wstrb  (m00_axi_wstrb),
        .m_uart_bresp  (m00_axi_bresp),   .m_uart_bvalid (m00_axi_bvalid),
        .m_uart_bready (m00_axi_bready),
        .m_uart_araddr (m00_axi_araddr),  .m_uart_arvalid(m00_axi_arvalid),
        .m_uart_arready(m00_axi_arready),
        .m_uart_rdata  (m00_axi_rdata),   .m_uart_rresp  (m00_axi_rresp),
        .m_uart_rvalid (m00_axi_rvalid),  .m_uart_rready (m00_axi_rready),

        .m_cnn_awaddr  (m01_axi_awaddr),  .m_cnn_awvalid (m01_axi_awvalid),
        .m_cnn_awready (m01_axi_awready),
        .m_cnn_wdata   (m01_axi_wdata),   .m_cnn_wvalid  (m01_axi_wvalid),
        .m_cnn_wready  (m01_axi_wready),  .m_cnn_wstrb   (m01_axi_wstrb),
        .m_cnn_bresp   (m01_axi_bresp),   .m_cnn_bvalid  (m01_axi_bvalid),
        .m_cnn_bready  (m01_axi_bready),
        .m_cnn_araddr  (m01_axi_araddr),  .m_cnn_arvalid (m01_axi_arvalid),
        .m_cnn_arready (m01_axi_arready),
        .m_cnn_rdata   (m01_axi_rdata),   .m_cnn_rresp   (m01_axi_rresp),
        .m_cnn_rvalid  (m01_axi_rvalid),  .m_cnn_rready  (m01_axi_rready)
    );

endmodule