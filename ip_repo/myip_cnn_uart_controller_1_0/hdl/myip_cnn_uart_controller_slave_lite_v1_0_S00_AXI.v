`timescale 1ns / 1ps
//==============================================================================
// myip_controller_S00_AXI.v
//
// UART IP <-> CNN IP 중간 제어기 (AXI4-Lite Slave + AXI4-Lite Master x2)
//
// 레지스터 맵 (Slave, 32-bit):
//   0x00  CTRL       W    [0]=enable (FSM 시작)
//   0x04  STATUS     R    [0]=busy, [1]=done
//   0x08  RESULT     R    [3:0]=class_idx (0~8)
//   0x0C  UART_BASE  R/W  UART IP 베이스 주소 (기본 0x43C0_0000)
//   0x10  CNN_BASE   R/W  CNN  IP 베이스 주소 (기본 0x43C2_0000)
//
// FSM 흐름:
//   IDLE → RX (2304바이트 수신)
//        → CNN_LOAD (픽셀 2304회 write)
//        → CNN_RUN  (start → done 폴링)
//        → CNN_RESULT (result 레지스터 읽기)
//        → TX  (클래스명 문자열 전송)
//        → DONE
//==============================================================================

module myip_controller_S00_AXI #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer IMG_N = 2304,  // 실제:2304 시뮬:10
    parameter integer C_S_AXI_ADDR_WIDTH = 5
)(
    // ── AXI4-Lite Slave ─────────────────────────────────────────────
    input  wire        S_AXI_ACLK,
    input  wire        S_AXI_ARESETN,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] S_AXI_AWADDR,
    input  wire [2:0]  S_AXI_AWPROT,
    input  wire        S_AXI_AWVALID,
    output wire        S_AXI_AWREADY,
    input  wire [C_S_AXI_DATA_WIDTH-1:0] S_AXI_WDATA,
    input  wire [3:0]  S_AXI_WSTRB,
    input  wire        S_AXI_WVALID,
    output wire        S_AXI_WREADY,
    output wire [1:0]  S_AXI_BRESP,
    output wire        S_AXI_BVALID,
    input  wire        S_AXI_BREADY,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] S_AXI_ARADDR,
    input  wire [2:0]  S_AXI_ARPROT,
    input  wire        S_AXI_ARVALID,
    output wire        S_AXI_ARREADY,
    output wire [C_S_AXI_DATA_WIDTH-1:0] S_AXI_RDATA,
    output wire [1:0]  S_AXI_RRESP,
    output wire        S_AXI_RVALID,
    input  wire        S_AXI_RREADY,

    // ── AXI4-Lite Master → UART IP ──────────────────────────────────
    output reg  [31:0] m_uart_awaddr,
    output reg         m_uart_awvalid,
    input  wire        m_uart_awready,
    output reg  [31:0] m_uart_wdata,
    output reg         m_uart_wvalid,
    input  wire        m_uart_wready,
    output wire [3:0]  m_uart_wstrb,
    input  wire [1:0]  m_uart_bresp,
    input  wire        m_uart_bvalid,
    output reg         m_uart_bready,
    output reg  [31:0] m_uart_araddr,
    output reg         m_uart_arvalid,
    input  wire        m_uart_arready,
    input  wire [31:0] m_uart_rdata,
    input  wire [1:0]  m_uart_rresp,
    input  wire        m_uart_rvalid,
    output reg         m_uart_rready,

    // ── AXI4-Lite Master → CNN IP ────────────────────────────────────
    output reg  [31:0] m_cnn_awaddr,
    output reg         m_cnn_awvalid,
    input  wire        m_cnn_awready,
    output reg  [31:0] m_cnn_wdata,
    output reg         m_cnn_wvalid,
    input  wire        m_cnn_wready,
    output wire [3:0]  m_cnn_wstrb,
    input  wire [1:0]  m_cnn_bresp,
    input  wire        m_cnn_bvalid,
    output reg         m_cnn_bready,
    output reg  [31:0] m_cnn_araddr,
    output reg         m_cnn_arvalid,
    input  wire        m_cnn_arready,
    input  wire [31:0] m_cnn_rdata,
    input  wire [1:0]  m_cnn_rresp,
    input  wire        m_cnn_rvalid,
    output reg         m_cnn_rready
);

    assign m_uart_wstrb = 4'hF;
    assign m_cnn_wstrb  = 4'hF;

    // ── Slave 내부 레지스터 ─────────────────────────────────────────
    localparam ADDR_LSB          = (C_S_AXI_DATA_WIDTH/32) + 1;
    localparam OPT_MEM_ADDR_BITS = 2;

    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr_r, axi_araddr_r;
    reg axi_awready_r, axi_wready_r, axi_bvalid_r;
    reg axi_arready_r, axi_rvalid_r;

    assign S_AXI_AWREADY = axi_awready_r;
    assign S_AXI_WREADY  = axi_wready_r;
    assign S_AXI_BRESP   = 2'b00;
    assign S_AXI_BVALID  = axi_bvalid_r;
    assign S_AXI_ARREADY = axi_arready_r;
    assign S_AXI_RRESP   = 2'b00;
    assign S_AXI_RVALID  = axi_rvalid_r;

    reg [31:0] reg_ctrl;       // 0x00
    reg [31:0] reg_uart_base;  // 0x0C
    reg [31:0] reg_cnn_base;   // 0x10

    // FSM 상태 → Slave 읽기
    reg fsm_busy, fsm_done;
    reg [3:0] fsm_class;

    // ── Slave Write FSM ─────────────────────────────────────────────
    reg [1:0] sw_state;
    localparam SW_IDLE=2'd0, SW_ADDR=2'd1, SW_DATA=2'd2;

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_awready_r <= 0; axi_wready_r <= 0; axi_bvalid_r <= 0;
            axi_awaddr_r  <= 0; sw_state <= SW_IDLE;
            reg_ctrl      <= 0;
            reg_uart_base <= 32'h43C0_0000;
            reg_cnn_base  <= 32'h43C2_0000;
        end else begin
            case (sw_state)
                SW_IDLE: begin axi_awready_r<=1; axi_wready_r<=1; sw_state<=SW_ADDR; end
                SW_ADDR: begin
                    if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                        axi_awaddr_r <= S_AXI_AWADDR;
                        if (S_AXI_WVALID) begin
                            axi_awready_r<=1; sw_state<=SW_ADDR; axi_bvalid_r<=1;
                        end else begin
                            axi_awready_r<=0; sw_state<=SW_DATA;
                            if (S_AXI_BREADY && axi_bvalid_r) axi_bvalid_r<=0;
                        end
                    end else begin
                        if (S_AXI_BREADY && axi_bvalid_r) axi_bvalid_r<=0;
                    end
                end
                SW_DATA: begin
                    if (S_AXI_WVALID) begin
                        sw_state<=SW_ADDR; axi_bvalid_r<=1; axi_awready_r<=1;
                    end else begin
                        if (S_AXI_BREADY && axi_bvalid_r) axi_bvalid_r<=0;
                    end
                end
            endcase

            if (S_AXI_WVALID) begin
                case ((S_AXI_AWVALID) ?
                      S_AXI_AWADDR[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] :
                      axi_awaddr_r[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB])
                    3'h0: reg_ctrl      <= S_AXI_WDATA;
                    3'h3: reg_uart_base <= S_AXI_WDATA;
                    3'h4: reg_cnn_base  <= S_AXI_WDATA;
                    default: ;
                endcase
            end
            // CTRL[0] 자동 클리어
            if (reg_ctrl[0] && fsm_busy) reg_ctrl[0] <= 0;
        end
    end

    // ── Slave Read FSM ──────────────────────────────────────────────
    reg [1:0] sr_state;
    localparam SR_IDLE=2'd0, SR_ADDR=2'd1, SR_DATA=2'd2;

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            axi_arready_r<=0; axi_rvalid_r<=0; axi_araddr_r<=0; sr_state<=SR_IDLE;
        end else begin
            case (sr_state)
                SR_IDLE: begin axi_arready_r<=1; sr_state<=SR_ADDR; end
                SR_ADDR: begin
                    if (S_AXI_ARVALID && S_AXI_ARREADY) begin
                        axi_araddr_r<=S_AXI_ARADDR; axi_rvalid_r<=1;
                        axi_arready_r<=0; sr_state<=SR_DATA;
                    end
                end
                SR_DATA: begin
                    if (S_AXI_RVALID && S_AXI_RREADY) begin
                        axi_rvalid_r<=0; axi_arready_r<=1; sr_state<=SR_ADDR;
                    end
                end
            endcase
        end
    end

    assign S_AXI_RDATA =
        (axi_araddr_r[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB]==3'h0) ? reg_ctrl :
        (axi_araddr_r[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB]==3'h1) ? {30'd0, fsm_done, fsm_busy} :
        (axi_araddr_r[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB]==3'h2) ? {28'd0, fsm_class} :
        (axi_araddr_r[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB]==3'h3) ? reg_uart_base :
        (axi_araddr_r[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB]==3'h4) ? reg_cnn_base  :
        32'd0;

    // ── 클래스명 ROM ────────────────────────────────────────────────
    // 9클래스 × 12바이트, null 종료 문자열
    reg [7:0] cls_rom [0:107];
    integer i;
    initial begin
        for (i=0; i<108; i=i+1) cls_rom[i] = 8'h00;
        // 0: Center\n  (7)
        cls_rom[0]=8'h43;cls_rom[1]=8'h65;cls_rom[2]=8'h6E;
        cls_rom[3]=8'h74;cls_rom[4]=8'h65;cls_rom[5]=8'h72;cls_rom[6]=8'h0A;
        // 1: Donut\n   (6)
        cls_rom[12]=8'h44;cls_rom[13]=8'h6F;cls_rom[14]=8'h6E;
        cls_rom[15]=8'h75;cls_rom[16]=8'h74;cls_rom[17]=8'h0A;
        // 2: Edge-Loc\n (9)
        cls_rom[24]=8'h45;cls_rom[25]=8'h64;cls_rom[26]=8'h67;
        cls_rom[27]=8'h65;cls_rom[28]=8'h2D;cls_rom[29]=8'h4C;
        cls_rom[30]=8'h6F;cls_rom[31]=8'h63;cls_rom[32]=8'h0A;
        // 3: Edge-Ring\n (10)
        cls_rom[36]=8'h45;cls_rom[37]=8'h64;cls_rom[38]=8'h67;
        cls_rom[39]=8'h65;cls_rom[40]=8'h2D;cls_rom[41]=8'h52;
        cls_rom[42]=8'h69;cls_rom[43]=8'h6E;cls_rom[44]=8'h67;cls_rom[45]=8'h0A;
        // 4: Loc\n     (4)
        cls_rom[48]=8'h4C;cls_rom[49]=8'h6F;cls_rom[50]=8'h63;cls_rom[51]=8'h0A;
        // 5: Near-full\n (10)
        cls_rom[60]=8'h4E;cls_rom[61]=8'h65;cls_rom[62]=8'h61;
        cls_rom[63]=8'h72;cls_rom[64]=8'h2D;cls_rom[65]=8'h66;
        cls_rom[66]=8'h75;cls_rom[67]=8'h6C;cls_rom[68]=8'h6C;cls_rom[69]=8'h0A;
        // 6: None\n    (5)
        cls_rom[72]=8'h4E;cls_rom[73]=8'h6F;cls_rom[74]=8'h6E;
        cls_rom[75]=8'h65;cls_rom[76]=8'h0A;
        // 7: Random\n  (7)
        cls_rom[84]=8'h52;cls_rom[85]=8'h61;cls_rom[86]=8'h6E;
        cls_rom[87]=8'h64;cls_rom[88]=8'h6F;cls_rom[89]=8'h6D;cls_rom[90]=8'h0A;
        // 8: Scratch\n (8)
        cls_rom[96]=8'h53;cls_rom[97]=8'h63;cls_rom[98]=8'h72;
        cls_rom[99]=8'h61;cls_rom[100]=8'h74;cls_rom[101]=8'h63;
        cls_rom[102]=8'h68;cls_rom[103]=8'h0A;
    end

    // ── 메인 제어 FSM ───────────────────────────────────────────────
    localparam [4:0]
        ST_IDLE       = 5'd0,
        ST_RX_REQ     = 5'd1,   // UART STATUS 읽기 AR
        ST_RX_WAIT    = 5'd2,   // UART STATUS 읽기 R
        ST_RX_DATAR   = 5'd3,   // UART RX_DATA AR
        ST_RX_DATAW   = 5'd4,   // UART RX_DATA R
        ST_RX_CLR_AW  = 5'd5,   // UART CTRL RST_ERR AW+W
        ST_RX_CLR_B   = 5'd6,   // RST_ERR B 대기
        ST_CNN_AW     = 5'd7,   // CNN IMG_ADDR AW+W
        ST_CNN_AWB    = 5'd8,   // CNN IMG_ADDR B
        ST_CNN_DW     = 5'd9,   // CNN IMG_DATA AW+W
        ST_CNN_DWB    = 5'd10,  // CNN IMG_DATA B
        ST_CNN_START  = 5'd11,  // CNN CTRL start AW+W
        ST_CNN_STARTB = 5'd12,  // start B
        ST_CNN_POLL   = 5'd13,  // CNN STATUS AR
        ST_CNN_POLLR  = 5'd14,  // CNN STATUS R
        ST_CNN_RES    = 5'd15,  // CNN RESULT AR
        ST_CNN_RESR   = 5'd16,  // CNN RESULT R
        ST_TX_CHK     = 5'd17,  // UART STATUS AR (TX_BUSY 확인)
        ST_TX_CHKR    = 5'd18,  // UART STATUS R
        ST_TX_SEND    = 5'd19,  // UART TX_DATA AW+W
        ST_TX_SENDB   = 5'd20,  // TX_DATA B
        ST_DONE       = 5'd21;

    reg [4:0]  st;
    reg [11:0] rx_cnt;       // 수신 픽셀 인덱스 (0~2303)
    reg [3:0]  tx_ci;        // 현재 전송 중인 문자 인덱스 (0~11)
    reg [7:0]  img_buf [0:IMG_N-1];

    // tx_rom_addr = class_idx * 12 + tx_ci
    wire [6:0] tx_rom_addr = (fsm_class * 4'd12) + {3'd0, tx_ci};

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            st          <= ST_IDLE;
            rx_cnt      <= 0;
            tx_ci       <= 0;
            fsm_busy    <= 0;
            fsm_done    <= 0;
            fsm_class   <= 0;
            m_uart_awvalid<=0; m_uart_wvalid<=0; m_uart_bready<=0;
            m_uart_arvalid<=0; m_uart_rready<=0;
            m_cnn_awvalid <=0; m_cnn_wvalid <=0; m_cnn_bready <=0;
            m_cnn_arvalid <=0; m_cnn_rready <=0;
        end else begin
            case (st)
                // ─────────────────────────────────────────────
                ST_IDLE: begin
                    fsm_busy <= 0;
                    if (reg_ctrl[0]) begin
                        fsm_busy <= 1; fsm_done <= 0;
                        rx_cnt   <= 0;
                        st       <= ST_RX_REQ;
                    end
                end

                // ─── UART STATUS 읽기 (RX_DONE[2] 확인) ─────
                ST_RX_REQ: begin
                    m_uart_araddr  <= reg_uart_base + 32'h10; // STATUS
                    m_uart_arvalid <= 1;
                    m_uart_rready  <= 1;
                    st <= ST_RX_WAIT;
                end
                ST_RX_WAIT: begin
                    if (m_uart_arvalid && m_uart_arready) m_uart_arvalid <= 0;
                    if (m_uart_rvalid) begin
                        m_uart_rready <= 0;
                        st <= m_uart_rdata[2] ? ST_RX_DATAR : ST_RX_REQ;
                    end
                end

                // ─── UART RX_DATA 읽기 ───────────────────────
                ST_RX_DATAR: begin
                    m_uart_araddr  <= reg_uart_base + 32'h0C; // RX_DATA
                    m_uart_arvalid <= 1;
                    m_uart_rready  <= 1;
                    st <= ST_RX_DATAW;
                end
                ST_RX_DATAW: begin
                    if (m_uart_arvalid && m_uart_arready) m_uart_arvalid <= 0;
                    if (m_uart_rvalid) begin
                        m_uart_rready <= 0;
                        img_buf[rx_cnt] <= m_uart_rdata[7:0];
                        st <= ST_RX_CLR_AW;
                    end
                end

                // ─── UART RST_ERR (done 래치 클리어) ─────────
                ST_RX_CLR_AW: begin
                    m_uart_awaddr  <= reg_uart_base + 32'h00;
                    m_uart_awvalid <= 1;
                    m_uart_wdata   <= 32'h04; // CTRL[2]=RST_ERR
                    m_uart_wvalid  <= 1;
                    m_uart_bready  <= 1;
                    st <= ST_RX_CLR_B;
                end
                ST_RX_CLR_B: begin
                    if (m_uart_awvalid && m_uart_awready) m_uart_awvalid <= 0;
                    if (m_uart_wvalid  && m_uart_wready)  m_uart_wvalid  <= 0;
                    if (m_uart_bvalid) begin
                        m_uart_bready <= 0;
                        if (rx_cnt == IMG_N-1) begin
                            rx_cnt <= 0; st <= ST_CNN_AW;
                        end else begin
                            rx_cnt <= rx_cnt + 1; st <= ST_RX_REQ;
                        end
                    end
                end

                // ─── CNN IMG_ADDR write ───────────────────────
                ST_CNN_AW: begin
                    m_cnn_awaddr  <= reg_cnn_base + 32'h0C;
                    m_cnn_awvalid <= 1;
                    m_cnn_wdata   <= {20'd0, rx_cnt};
                    m_cnn_wvalid  <= 1;
                    m_cnn_bready  <= 1;
                    st <= ST_CNN_AWB;
                end
                ST_CNN_AWB: begin
                    if (m_cnn_awvalid && m_cnn_awready) m_cnn_awvalid <= 0;
                    if (m_cnn_wvalid  && m_cnn_wready)  m_cnn_wvalid  <= 0;
                    if (m_cnn_bvalid) begin
                        m_cnn_bready <= 0; st <= ST_CNN_DW;
                    end
                end

                // ─── CNN IMG_DATA write ───────────────────────
                ST_CNN_DW: begin
                    m_cnn_awaddr  <= reg_cnn_base + 32'h10;
                    m_cnn_awvalid <= 1;
                    m_cnn_wdata   <= {24'd0, img_buf[rx_cnt]};
                    m_cnn_wvalid  <= 1;
                    m_cnn_bready  <= 1;
                    st <= ST_CNN_DWB;
                end
                ST_CNN_DWB: begin
                    if (m_cnn_awvalid && m_cnn_awready) m_cnn_awvalid <= 0;
                    if (m_cnn_wvalid  && m_cnn_wready)  m_cnn_wvalid  <= 0;
                    if (m_cnn_bvalid) begin
                        m_cnn_bready <= 0;
                        if (rx_cnt == IMG_N-1) begin
                            rx_cnt <= 0; st <= ST_CNN_START;
                        end else begin
                            rx_cnt <= rx_cnt + 1; st <= ST_CNN_AW;
                        end
                    end
                end

                // ─── CNN start ────────────────────────────────
                ST_CNN_START: begin
                    m_cnn_awaddr  <= reg_cnn_base + 32'h00;
                    m_cnn_awvalid <= 1;
                    m_cnn_wdata   <= 32'h01; // CTRL[0]=start
                    m_cnn_wvalid  <= 1;
                    m_cnn_bready  <= 1;
                    st <= ST_CNN_STARTB;
                end
                ST_CNN_STARTB: begin
                    if (m_cnn_awvalid && m_cnn_awready) m_cnn_awvalid <= 0;
                    if (m_cnn_wvalid  && m_cnn_wready)  m_cnn_wvalid  <= 0;
                    if (m_cnn_bvalid) begin
                        m_cnn_bready <= 0; st <= ST_CNN_POLL;
                    end
                end

                // ─── CNN STATUS 폴링 (done[0]) ────────────────
                ST_CNN_POLL: begin
                    m_cnn_araddr  <= reg_cnn_base + 32'h04;
                    m_cnn_arvalid <= 1;
                    m_cnn_rready  <= 1;
                    st <= ST_CNN_POLLR;
                end
                ST_CNN_POLLR: begin
                    if (m_cnn_arvalid && m_cnn_arready) m_cnn_arvalid <= 0;
                    if (m_cnn_rvalid) begin
                        m_cnn_rready <= 0;
                        st <= m_cnn_rdata[0] ? ST_CNN_RES : ST_CNN_POLL;
                    end
                end

                // ─── CNN RESULT 읽기 ──────────────────────────
                ST_CNN_RES: begin
                    m_cnn_araddr  <= reg_cnn_base + 32'h08;
                    m_cnn_arvalid <= 1;
                    m_cnn_rready  <= 1;
                    st <= ST_CNN_RESR;
                end
                ST_CNN_RESR: begin
                    if (m_cnn_arvalid && m_cnn_arready) m_cnn_arvalid <= 0;
                    if (m_cnn_rvalid) begin
                        m_cnn_rready <= 0;
                        fsm_class    <= m_cnn_rdata[3:0];
                        tx_ci        <= 0;
                        st           <= ST_TX_CHK;
                    end
                end

                // ─── UART TX_BUSY 확인 ────────────────────────
                ST_TX_CHK: begin
                    m_uart_araddr  <= reg_uart_base + 32'h10;
                    m_uart_arvalid <= 1;
                    m_uart_rready  <= 1;
                    st <= ST_TX_CHKR;
                end
                ST_TX_CHKR: begin
                    if (m_uart_arvalid && m_uart_arready) m_uart_arvalid <= 0;
                    if (m_uart_rvalid) begin
                        m_uart_rready <= 0;
                        st <= (!m_uart_rdata[0]) ? ST_TX_SEND : ST_TX_CHK;
                    end
                end

                // ─── UART TX_DATA write ───────────────────────
                ST_TX_SEND: begin
                    m_uart_awaddr  <= reg_uart_base + 32'h08;
                    m_uart_awvalid <= 1;
                    m_uart_wdata   <= {24'd0, cls_rom[tx_rom_addr]};
                    m_uart_wvalid  <= 1;
                    m_uart_bready  <= 1;
                    st <= ST_TX_SENDB;
                end
                ST_TX_SENDB: begin
                    if (m_uart_awvalid && m_uart_awready) m_uart_awvalid <= 0;
                    if (m_uart_wvalid  && m_uart_wready)  m_uart_wvalid  <= 0;
                    if (m_uart_bvalid) begin
                        m_uart_bready <= 0;
                        tx_ci <= tx_ci + 1;
                        // 다음 문자가 null(0x00)이거나 12번째면 종료
                        if (cls_rom[(fsm_class * 4'd12) + tx_ci + 1] == 8'h00 ||
                            tx_ci >= 4'd11) begin
                            fsm_done <= 1;
                            fsm_busy <= 0;
                            st       <= ST_DONE;
                        end else begin
                            st <= ST_TX_CHK;
                        end
                    end
                end

                ST_DONE: begin
                    // CTRL[0] 다시 쓰면 재실행
                    if (reg_ctrl[0]) begin
                        fsm_done <= 0; fsm_busy <= 1;
                        rx_cnt   <= 0; st       <= ST_RX_REQ;
                    end
                end

                default: st <= ST_IDLE;
            endcase
        end
    end

endmodule