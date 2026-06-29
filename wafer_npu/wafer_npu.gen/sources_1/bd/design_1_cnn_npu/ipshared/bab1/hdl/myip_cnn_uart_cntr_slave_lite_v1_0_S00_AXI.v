`timescale 1 ns / 1 ps

module myip_cnn_uart_cntr_slave_lite_v1_0_S00_AXI #
(
    // Users to add parameters here
    parameter integer IMG_N              = 2304,
    parameter integer C_M_AXI_ADDR_WIDTH = 32,
    parameter integer C_M_AXI_DATA_WIDTH = 32,
    // User parameters ends
    // Do not modify the parameters beyond this line
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 5
)
(
    // Users to add ports here
    // M_AXI Master port (UART/CNN IP control - single port)
    output reg  [C_M_AXI_ADDR_WIDTH-1:0] M_AXI_AWADDR,
    output wire [2:0]  M_AXI_AWPROT,
    output reg         M_AXI_AWVALID,
    input  wire        M_AXI_AWREADY,
    output reg  [C_M_AXI_DATA_WIDTH-1:0] M_AXI_WDATA,
    output wire [3:0]  M_AXI_WSTRB,
    output reg         M_AXI_WVALID,
    input  wire        M_AXI_WREADY,
    input  wire [1:0]  M_AXI_BRESP,
    input  wire        M_AXI_BVALID,
    output reg         M_AXI_BREADY,
    output reg  [C_M_AXI_ADDR_WIDTH-1:0] M_AXI_ARADDR,
    output wire [2:0]  M_AXI_ARPROT,
    output reg         M_AXI_ARVALID,
    input  wire        M_AXI_ARREADY,
    input  wire [C_M_AXI_DATA_WIDTH-1:0] M_AXI_RDATA,
    input  wire [1:0]  M_AXI_RRESP,
    input  wire        M_AXI_RVALID,
    output reg         M_AXI_RREADY,
    // User ports ends
    // Do not modify the ports beyond this line

    input wire  S_AXI_ACLK,
    input wire  S_AXI_ARESETN,
    input wire [C_S_AXI_ADDR_WIDTH-1:0] S_AXI_AWADDR,
    input wire [2:0] S_AXI_AWPROT,
    input wire  S_AXI_AWVALID,
    output wire S_AXI_AWREADY,
    input wire [C_S_AXI_DATA_WIDTH-1:0] S_AXI_WDATA,
    input wire [(C_S_AXI_DATA_WIDTH/8)-1:0] S_AXI_WSTRB,
    input wire  S_AXI_WVALID,
    output wire S_AXI_WREADY,
    output wire [1:0] S_AXI_BRESP,
    output wire S_AXI_BVALID,
    input wire  S_AXI_BREADY,
    input wire [C_S_AXI_ADDR_WIDTH-1:0] S_AXI_ARADDR,
    input wire [2:0] S_AXI_ARPROT,
    input wire  S_AXI_ARVALID,
    output wire S_AXI_ARREADY,
    output wire [C_S_AXI_DATA_WIDTH-1:0] S_AXI_RDATA,
    output wire [1:0] S_AXI_RRESP,
    output wire S_AXI_RVALID,
    input wire  S_AXI_RREADY
);

    // Master port: fixed signals
    assign M_AXI_AWPROT = 3'd0;
    assign M_AXI_WSTRB  = 4'hF;
    assign M_AXI_ARPROT = 3'd0;

    // AXI4-Lite Slave signals
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr;
    reg axi_awready, axi_wready, axi_bvalid;
    reg [1:0] axi_bresp;
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_araddr;
    reg axi_arready, axi_rvalid;
    reg [1:0] axi_rresp;

    localparam integer ADDR_LSB          = (C_S_AXI_DATA_WIDTH/32) + 1;
    localparam integer OPT_MEM_ADDR_BITS = 2;

    // slv_reg0 = CTRL       (0x00): [0]=enable
    // slv_reg1 = STATUS     (0x04): R [0]=busy [1]=done
    // slv_reg2 = RESULT     (0x08): R [3:0]=class_idx
    // slv_reg3 = UART_BASE  (0x0C): R/W  default 0x43C1_0000
    // slv_reg4 = CNN_BASE   (0x10): R/W  default 0x43C2_0000
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg0;
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg1;
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg2;
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg3;
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg4;
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg5;
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg6;
    reg [C_S_AXI_DATA_WIDTH-1:0] slv_reg7;
    integer byte_index;

    assign S_AXI_AWREADY = axi_awready;
    assign S_AXI_WREADY  = axi_wready;
    assign S_AXI_BRESP   = axi_bresp;
    assign S_AXI_BVALID  = axi_bvalid;
    assign S_AXI_ARREADY = axi_arready;
    assign S_AXI_RRESP   = axi_rresp;
    assign S_AXI_RVALID  = axi_rvalid;

    reg [1:0] state_write;
    reg [1:0] state_read;
    localparam Idle = 2'b00, Raddr = 2'b10, Rdata = 2'b11, Waddr = 2'b10, Wdata = 2'b11;

    // FSM internal signals
    reg fsm_busy, fsm_done;
    reg [3:0] fsm_class;

    // ── Slave Write FSM (template 그대로 유지) ────────────────────
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_awready <= 0; axi_wready <= 0; axi_bvalid <= 0;
            axi_bresp <= 0; axi_awaddr <= 0; state_write <= Idle;
        end else begin
            case(state_write)
                Idle: begin
                    if (S_AXI_ARESETN == 1'b1) begin
                        axi_awready <= 1'b1; axi_wready <= 1'b1;
                        state_write <= Waddr;
                    end else state_write <= state_write;
                end
                Waddr: begin
                    if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                        axi_awaddr <= S_AXI_AWADDR;
                        if (S_AXI_WVALID) begin
                            axi_awready <= 1'b1; state_write <= Waddr; axi_bvalid <= 1'b1;
                        end else begin
                            axi_awready <= 1'b0; state_write <= Wdata;
                            if (S_AXI_BREADY && axi_bvalid) axi_bvalid <= 1'b0;
                        end
                    end else begin
                        state_write <= state_write;
                        if (S_AXI_BREADY && axi_bvalid) axi_bvalid <= 1'b0;
                    end
                end
                Wdata: begin
                    if (S_AXI_WVALID) begin
                        state_write <= Waddr; axi_bvalid <= 1'b1; axi_awready <= 1'b1;
                    end else begin
                        state_write <= state_write;
                        if (S_AXI_BREADY && axi_bvalid) axi_bvalid <= 1'b0;
                    end
                end
            endcase
        end
    end

    // ── Slave 레지스터 Write ──────────────────────────────────────
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            slv_reg0 <= 0;
            slv_reg1 <= 0;
            slv_reg2 <= 0;
            slv_reg3 <= 32'h43C1_0000;  // UART_BASE default
            slv_reg4 <= 32'h43C2_0000;  // CNN_BASE  default
            slv_reg5 <= 0;
            slv_reg6 <= 0;
            slv_reg7 <= 0;
        end else begin
            if (S_AXI_WVALID) begin
                case ((S_AXI_AWVALID) ?
                      S_AXI_AWADDR[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] :
                      axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB])
                    3'h0: for (byte_index=0; byte_index<=(C_S_AXI_DATA_WIDTH/8)-1; byte_index=byte_index+1)
                              if (S_AXI_WSTRB[byte_index]) slv_reg0[(byte_index*8)+:8] <= S_AXI_WDATA[(byte_index*8)+:8];
                    // 3'h1: STATUS  read-only
                    // 3'h2: RESULT  read-only
                    3'h3: for (byte_index=0; byte_index<=(C_S_AXI_DATA_WIDTH/8)-1; byte_index=byte_index+1)
                              if (S_AXI_WSTRB[byte_index]) slv_reg3[(byte_index*8)+:8] <= S_AXI_WDATA[(byte_index*8)+:8];
                    3'h4: for (byte_index=0; byte_index<=(C_S_AXI_DATA_WIDTH/8)-1; byte_index=byte_index+1)
                              if (S_AXI_WSTRB[byte_index]) slv_reg4[(byte_index*8)+:8] <= S_AXI_WDATA[(byte_index*8)+:8];
                    default: ;
                endcase
            end
            // CTRL[0] auto-clear after FSM starts
            if (slv_reg0[0] && fsm_busy) slv_reg0[0] <= 1'b0;
        end
    end

    // ── Slave Read FSM (template 그대로 유지) ─────────────────────
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_arready <= 1'b0; axi_rvalid <= 1'b0;
            axi_rresp <= 1'b0; state_read <= Idle;
        end else begin
            case(state_read)
                Idle: begin
                    if (S_AXI_ARESETN == 1'b1) begin
                        state_read <= Raddr; axi_arready <= 1'b1;
                    end else state_read <= state_read;
                end
                Raddr: begin
                    if (S_AXI_ARVALID && S_AXI_ARREADY) begin
                        state_read <= Rdata; axi_araddr <= S_AXI_ARADDR;
                        axi_rvalid <= 1'b1; axi_arready <= 1'b0;
                    end else state_read <= state_read;
                end
                Rdata: begin
                    if (S_AXI_RVALID && S_AXI_RREADY) begin
                        axi_rvalid <= 1'b0; axi_arready <= 1'b1;
                        state_read <= Raddr;
                    end else state_read <= state_read;
                end
            endcase
        end
    end

    // ── Slave Read 반환값 ─────────────────────────────────────────
    assign S_AXI_RDATA =
        (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB]==3'h0) ? slv_reg0 :
        (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB]==3'h1) ? {30'd0, fsm_done, fsm_busy} :
        (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB]==3'h2) ? {28'd0, fsm_class} :
        (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB]==3'h3) ? slv_reg3 :
        (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB]==3'h4) ? slv_reg4 :
        32'd0;

    // ── Class name ROM ────────────────────────────────────────────
    // 9 classes x 12 bytes, null-terminated
    reg [7:0] cls_rom [0:107];
    integer ri;
    initial begin
        for (ri=0; ri<108; ri=ri+1) cls_rom[ri] = 8'h00;
        // 0: Center\n
        cls_rom[0]=8'h43; cls_rom[1]=8'h65; cls_rom[2]=8'h6E;
        cls_rom[3]=8'h74; cls_rom[4]=8'h65; cls_rom[5]=8'h72; cls_rom[6]=8'h0A;
        // 1: Donut\n
        cls_rom[12]=8'h44; cls_rom[13]=8'h6F; cls_rom[14]=8'h6E;
        cls_rom[15]=8'h75; cls_rom[16]=8'h74; cls_rom[17]=8'h0A;
        // 2: Edge-Loc\n
        cls_rom[24]=8'h45; cls_rom[25]=8'h64; cls_rom[26]=8'h67;
        cls_rom[27]=8'h65; cls_rom[28]=8'h2D; cls_rom[29]=8'h4C;
        cls_rom[30]=8'h6F; cls_rom[31]=8'h63; cls_rom[32]=8'h0A;
        // 3: Edge-Ring\n
        cls_rom[36]=8'h45; cls_rom[37]=8'h64; cls_rom[38]=8'h67;
        cls_rom[39]=8'h65; cls_rom[40]=8'h2D; cls_rom[41]=8'h52;
        cls_rom[42]=8'h69; cls_rom[43]=8'h6E; cls_rom[44]=8'h67; cls_rom[45]=8'h0A;
        // 4: Loc\n
        cls_rom[48]=8'h4C; cls_rom[49]=8'h6F; cls_rom[50]=8'h63; cls_rom[51]=8'h0A;
        // 5: Near-full\n
        cls_rom[60]=8'h4E; cls_rom[61]=8'h65; cls_rom[62]=8'h61;
        cls_rom[63]=8'h72; cls_rom[64]=8'h2D; cls_rom[65]=8'h66;
        cls_rom[66]=8'h75; cls_rom[67]=8'h6C; cls_rom[68]=8'h6C; cls_rom[69]=8'h0A;
        // 6: None\n
        cls_rom[72]=8'h4E; cls_rom[73]=8'h6F; cls_rom[74]=8'h6E;
        cls_rom[75]=8'h65; cls_rom[76]=8'h0A;
        // 7: Random\n
        cls_rom[84]=8'h52; cls_rom[85]=8'h61; cls_rom[86]=8'h6E;
        cls_rom[87]=8'h64; cls_rom[88]=8'h6F; cls_rom[89]=8'h6D; cls_rom[90]=8'h0A;
        // 8: Scratch\n
        cls_rom[96]=8'h53; cls_rom[97]=8'h63; cls_rom[98]=8'h72;
        cls_rom[99]=8'h61; cls_rom[100]=8'h74; cls_rom[101]=8'h63;
        cls_rom[102]=8'h68; cls_rom[103]=8'h0A;
    end

    // ── Main FSM ──────────────────────────────────────────────────
    localparam [4:0]
        ST_IDLE      = 5'd0,
        ST_RX_REQ    = 5'd1,   // UART STATUS AR
        ST_RX_WAIT   = 5'd2,   // UART STATUS R
        ST_RX_DATAR  = 5'd3,   // UART RX_DATA AR
        ST_RX_DATAW  = 5'd4,   // UART RX_DATA R
        ST_RX_CLR_AW = 5'd5,   // UART RST_ERR AW+W
        ST_RX_CLR_B  = 5'd6,   // RST_ERR B
        ST_CNN_AW    = 5'd7,   // CNN IMG_ADDR AW+W
        ST_CNN_AWB   = 5'd8,
        ST_CNN_DW    = 5'd9,   // CNN IMG_DATA AW+W
        ST_CNN_DWB   = 5'd10,
        ST_CNN_START = 5'd11,  // CNN CTRL start
        ST_CNN_STARTB= 5'd12,
        ST_CNN_POLL  = 5'd13,  // CNN STATUS AR
        ST_CNN_POLLR = 5'd14,
        ST_CNN_RES   = 5'd15,  // CNN RESULT AR
        ST_CNN_RESR  = 5'd16,
        ST_TX_CHK    = 5'd17,  // UART TX_BUSY AR
        ST_TX_CHKR   = 5'd18,
        ST_TX_SEND   = 5'd19,  // UART TX_DATA AW+W
        ST_TX_SENDB  = 5'd20,
        ST_DONE      = 5'd21;

    reg [4:0]  st;
    reg [11:0] rx_cnt;
    reg [3:0]  tx_ci;
    reg [7:0]  img_buf [0:IMG_N-1];

    wire [6:0] tx_rom_addr = (fsm_class * 4'd12) + {3'd0, tx_ci};

    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            st <= ST_IDLE; rx_cnt <= 0; tx_ci <= 0;
            fsm_busy <= 0; fsm_done <= 0; fsm_class <= 0;
            M_AXI_AWVALID<=0; M_AXI_WVALID<=0; M_AXI_BREADY<=0;
            M_AXI_ARVALID<=0; M_AXI_RREADY<=0;
            M_AXI_AWADDR<=0; M_AXI_WDATA<=0; M_AXI_ARADDR<=0;
        end else begin
            case (st)
                ST_IDLE: begin
                    fsm_busy <= 0;
                    if (slv_reg0[0]) begin
                        fsm_busy<=1; fsm_done<=0; rx_cnt<=0; st<=ST_RX_REQ;
                    end
                end
                ST_RX_REQ: begin
                    M_AXI_ARADDR<=slv_reg3+32'h10; M_AXI_ARVALID<=1; M_AXI_RREADY<=1;
                    st<=ST_RX_WAIT;
                end
                ST_RX_WAIT: begin
                    if (M_AXI_ARVALID&&M_AXI_ARREADY) M_AXI_ARVALID<=0;
                    if (M_AXI_RVALID) begin
                        M_AXI_RREADY<=0;
                        st <= M_AXI_RDATA[2] ? ST_RX_DATAR : ST_RX_REQ;
                    end
                end
                ST_RX_DATAR: begin
                    M_AXI_ARADDR<=slv_reg3+32'h0C; M_AXI_ARVALID<=1; M_AXI_RREADY<=1;
                    st<=ST_RX_DATAW;
                end
                ST_RX_DATAW: begin
                    if (M_AXI_ARVALID&&M_AXI_ARREADY) M_AXI_ARVALID<=0;
                    if (M_AXI_RVALID) begin
                        M_AXI_RREADY<=0;
                        img_buf[rx_cnt]<=M_AXI_RDATA[7:0]; st<=ST_RX_CLR_AW;
                    end
                end
                ST_RX_CLR_AW: begin
                    M_AXI_AWADDR<=slv_reg3+32'h00; M_AXI_AWVALID<=1;
                    M_AXI_WDATA<=32'h04; M_AXI_WVALID<=1; M_AXI_BREADY<=1;
                    st<=ST_RX_CLR_B;
                end
                ST_RX_CLR_B: begin
                    if (M_AXI_AWVALID&&M_AXI_AWREADY) M_AXI_AWVALID<=0;
                    if (M_AXI_WVALID&&M_AXI_WREADY)   M_AXI_WVALID<=0;
                    if (M_AXI_BVALID) begin
                        M_AXI_BREADY<=0;
                        if (rx_cnt==IMG_N-1) begin rx_cnt<=0; st<=ST_CNN_AW;
                        end else begin rx_cnt<=rx_cnt+1; st<=ST_RX_REQ; end
                    end
                end
                ST_CNN_AW: begin
                    M_AXI_AWADDR<=slv_reg4+32'h0C; M_AXI_AWVALID<=1;
                    M_AXI_WDATA<={20'd0,rx_cnt}; M_AXI_WVALID<=1; M_AXI_BREADY<=1;
                    st<=ST_CNN_AWB;
                end
                ST_CNN_AWB: begin
                    if (M_AXI_AWVALID&&M_AXI_AWREADY) M_AXI_AWVALID<=0;
                    if (M_AXI_WVALID&&M_AXI_WREADY)   M_AXI_WVALID<=0;
                    if (M_AXI_BVALID) begin M_AXI_BREADY<=0; st<=ST_CNN_DW; end
                end
                ST_CNN_DW: begin
                    M_AXI_AWADDR<=slv_reg4+32'h10; M_AXI_AWVALID<=1;
                    M_AXI_WDATA<={24'd0,img_buf[rx_cnt]}; M_AXI_WVALID<=1; M_AXI_BREADY<=1;
                    st<=ST_CNN_DWB;
                end
                ST_CNN_DWB: begin
                    if (M_AXI_AWVALID&&M_AXI_AWREADY) M_AXI_AWVALID<=0;
                    if (M_AXI_WVALID&&M_AXI_WREADY)   M_AXI_WVALID<=0;
                    if (M_AXI_BVALID) begin
                        M_AXI_BREADY<=0;
                        if (rx_cnt==IMG_N-1) begin rx_cnt<=0; st<=ST_CNN_START;
                        end else begin rx_cnt<=rx_cnt+1; st<=ST_CNN_AW; end
                    end
                end
                ST_CNN_START: begin
                    M_AXI_AWADDR<=slv_reg4+32'h00; M_AXI_AWVALID<=1;
                    M_AXI_WDATA<=32'h01; M_AXI_WVALID<=1; M_AXI_BREADY<=1;
                    st<=ST_CNN_STARTB;
                end
                ST_CNN_STARTB: begin
                    if (M_AXI_AWVALID&&M_AXI_AWREADY) M_AXI_AWVALID<=0;
                    if (M_AXI_WVALID&&M_AXI_WREADY)   M_AXI_WVALID<=0;
                    if (M_AXI_BVALID) begin M_AXI_BREADY<=0; st<=ST_CNN_POLL; end
                end
                ST_CNN_POLL: begin
                    M_AXI_ARADDR<=slv_reg4+32'h04; M_AXI_ARVALID<=1; M_AXI_RREADY<=1;
                    st<=ST_CNN_POLLR;
                end
                ST_CNN_POLLR: begin
                    if (M_AXI_ARVALID&&M_AXI_ARREADY) M_AXI_ARVALID<=0;
                    if (M_AXI_RVALID) begin
                        M_AXI_RREADY<=0;
                        st <= M_AXI_RDATA[0] ? ST_CNN_RES : ST_CNN_POLL;
                    end
                end
                ST_CNN_RES: begin
                    M_AXI_ARADDR<=slv_reg4+32'h08; M_AXI_ARVALID<=1; M_AXI_RREADY<=1;
                    st<=ST_CNN_RESR;
                end
                ST_CNN_RESR: begin
                    if (M_AXI_ARVALID&&M_AXI_ARREADY) M_AXI_ARVALID<=0;
                    if (M_AXI_RVALID) begin
                        M_AXI_RREADY<=0;
                        fsm_class<=M_AXI_RDATA[3:0]; tx_ci<=0; st<=ST_TX_CHK;
                    end
                end
                ST_TX_CHK: begin
                    M_AXI_ARADDR<=slv_reg3+32'h10; M_AXI_ARVALID<=1; M_AXI_RREADY<=1;
                    st<=ST_TX_CHKR;
                end
                ST_TX_CHKR: begin
                    if (M_AXI_ARVALID&&M_AXI_ARREADY) M_AXI_ARVALID<=0;
                    if (M_AXI_RVALID) begin
                        M_AXI_RREADY<=0;
                        st <= (!M_AXI_RDATA[0]) ? ST_TX_SEND : ST_TX_CHK;
                    end
                end
                ST_TX_SEND: begin
                    M_AXI_AWADDR<=slv_reg3+32'h08; M_AXI_AWVALID<=1;
                    M_AXI_WDATA<={24'd0,cls_rom[tx_rom_addr]}; M_AXI_WVALID<=1; M_AXI_BREADY<=1;
                    st<=ST_TX_SENDB;
                end
                ST_TX_SENDB: begin
                    if (M_AXI_AWVALID&&M_AXI_AWREADY) M_AXI_AWVALID<=0;
                    if (M_AXI_WVALID&&M_AXI_WREADY)   M_AXI_WVALID<=0;
                    if (M_AXI_BVALID) begin
                        M_AXI_BREADY<=0; tx_ci<=tx_ci+1;
                        if (cls_rom[(fsm_class*4'd12)+tx_ci+1]==8'h00 || tx_ci>=4'd11) begin
                            fsm_done<=1; fsm_busy<=0; st<=ST_DONE;
                        end else begin
                            st<=ST_TX_CHK;
                        end
                    end
                end
                ST_DONE: begin
                    if (slv_reg0[0]) begin
                        fsm_done<=0; fsm_busy<=1; rx_cnt<=0; st<=ST_RX_REQ;
                    end
                end
                default: st<=ST_IDLE;
            endcase
        end
    end

endmodule