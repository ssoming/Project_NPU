`timescale 1 ns / 1 ps

module myip_cnn_uart_cntr #
(
    // Users to add parameters here
    parameter integer IMG_N              = 2304,
    parameter integer C_M_AXI_ADDR_WIDTH = 32,
    parameter integer C_M_AXI_DATA_WIDTH = 32,
    // User parameters ends
    // Do not modify the parameters beyond this line

    parameter integer C_S00_AXI_DATA_WIDTH = 32,
    parameter integer C_S00_AXI_ADDR_WIDTH = 5
)
(
    // Users to add ports here
    // M_AXI Master port
    output wire [C_M_AXI_ADDR_WIDTH-1:0] m_axi_awaddr,
    output wire [2:0]  m_axi_awprot,
    output wire        m_axi_awvalid,
    input  wire        m_axi_awready,
    output wire [C_M_AXI_DATA_WIDTH-1:0] m_axi_wdata,
    output wire [3:0]  m_axi_wstrb,
    output wire        m_axi_wvalid,
    input  wire        m_axi_wready,
    input  wire [1:0]  m_axi_bresp,
    input  wire        m_axi_bvalid,
    output wire        m_axi_bready,
    output wire [C_M_AXI_ADDR_WIDTH-1:0] m_axi_araddr,
    output wire [2:0]  m_axi_arprot,
    output wire        m_axi_arvalid,
    input  wire        m_axi_arready,
    input  wire [C_M_AXI_DATA_WIDTH-1:0] m_axi_rdata,
    input  wire [1:0]  m_axi_rresp,
    input  wire        m_axi_rvalid,
    output wire        m_axi_rready,
    // User ports ends
    // Do not modify the ports beyond this line

    // Ports of Axi Slave Bus Interface S00_AXI
    input wire  s00_axi_aclk,
    input wire  s00_axi_aresetn,
    input wire [C_S00_AXI_ADDR_WIDTH-1:0] s00_axi_awaddr,
    input wire [2:0] s00_axi_awprot,
    input wire  s00_axi_awvalid,
    output wire s00_axi_awready,
    input wire [C_S00_AXI_DATA_WIDTH-1:0] s00_axi_wdata,
    input wire [(C_S00_AXI_DATA_WIDTH/8)-1:0] s00_axi_wstrb,
    input wire  s00_axi_wvalid,
    output wire s00_axi_wready,
    output wire [1:0] s00_axi_bresp,
    output wire s00_axi_bvalid,
    input wire  s00_axi_bready,
    input wire [C_S00_AXI_ADDR_WIDTH-1:0] s00_axi_araddr,
    input wire [2:0] s00_axi_arprot,
    input wire  s00_axi_arvalid,
    output wire s00_axi_arready,
    output wire [C_S00_AXI_DATA_WIDTH-1:0] s00_axi_rdata,
    output wire [1:0] s00_axi_rresp,
    output wire s00_axi_rvalid,
    input wire  s00_axi_rready
);

    myip_cnn_uart_cntr_slave_lite_v1_0_S00_AXI #(
        .IMG_N(IMG_N),
        .C_M_AXI_ADDR_WIDTH(C_M_AXI_ADDR_WIDTH),
        .C_M_AXI_DATA_WIDTH(C_M_AXI_DATA_WIDTH),
        .C_S_AXI_DATA_WIDTH(C_S00_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S00_AXI_ADDR_WIDTH)
    ) myip_cnn_uart_cntr_slave_lite_v1_0_S00_AXI_inst (
        .M_AXI_AWADDR (m_axi_awaddr),  .M_AXI_AWPROT(m_axi_awprot),
        .M_AXI_AWVALID(m_axi_awvalid), .M_AXI_AWREADY(m_axi_awready),
        .M_AXI_WDATA  (m_axi_wdata),   .M_AXI_WSTRB (m_axi_wstrb),
        .M_AXI_WVALID (m_axi_wvalid),  .M_AXI_WREADY(m_axi_wready),
        .M_AXI_BRESP  (m_axi_bresp),   .M_AXI_BVALID(m_axi_bvalid),
        .M_AXI_BREADY (m_axi_bready),
        .M_AXI_ARADDR (m_axi_araddr),  .M_AXI_ARPROT(m_axi_arprot),
        .M_AXI_ARVALID(m_axi_arvalid), .M_AXI_ARREADY(m_axi_arready),
        .M_AXI_RDATA  (m_axi_rdata),   .M_AXI_RRESP (m_axi_rresp),
        .M_AXI_RVALID (m_axi_rvalid),  .M_AXI_RREADY(m_axi_rready),
        .S_AXI_ACLK   (s00_axi_aclk),  .S_AXI_ARESETN(s00_axi_aresetn),
        .S_AXI_AWADDR (s00_axi_awaddr), .S_AXI_AWPROT(s00_axi_awprot),
        .S_AXI_AWVALID(s00_axi_awvalid),.S_AXI_AWREADY(s00_axi_awready),
        .S_AXI_WDATA  (s00_axi_wdata),  .S_AXI_WSTRB (s00_axi_wstrb),
        .S_AXI_WVALID (s00_axi_wvalid), .S_AXI_WREADY(s00_axi_wready),
        .S_AXI_BRESP  (s00_axi_bresp),  .S_AXI_BVALID(s00_axi_bvalid),
        .S_AXI_BREADY (s00_axi_bready),
        .S_AXI_ARADDR (s00_axi_araddr), .S_AXI_ARPROT(s00_axi_arprot),
        .S_AXI_ARVALID(s00_axi_arvalid),.S_AXI_ARREADY(s00_axi_arready),
        .S_AXI_RDATA  (s00_axi_rdata),  .S_AXI_RRESP (s00_axi_rresp),
        .S_AXI_RVALID (s00_axi_rvalid), .S_AXI_RREADY(s00_axi_rready)
    );

endmodule