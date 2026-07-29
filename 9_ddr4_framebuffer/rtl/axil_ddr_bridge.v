// =====================================================================
// MSA-2020 DDR4 帧缓存 —— axil_ddr_bridge
//   PCIe BAR0 (AXI-Lite, pcie_clk) -> [跨时钟 CDC] -> Avalon-MM (clk100M)
//   Avalon 主口接 jtag_sys.mem_* (EMIF 内部再跨到 DDR4 用户时钟, 由 qsys 处理)。
//
//   单发(single-outstanding)握手 + toggle 同步, 简单可靠。帧缓存吞吐足够。
//
//   BAR0 内存映射 (256KB, 18-bit):
//     addr[17]==0  : DDR4 数据窗口 (128KB). am_addr = {page_reg, addr[16:0]}
//     addr[17]==1  : 寄存器
//        0x20000 PAGE   (RW) DDR4 页选择 = am_address[35:17]
//        0x20004 STATUS (R)  bit0=cal_ok0 bit1=cal_ok1
//        0x2000C ID     (R)  0x44445242 "DDRB"
// =====================================================================
`resetall
`timescale 1ns / 1ps
`default_nettype none

module axil_ddr_bridge #
(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 18,
    parameter STRB_WIDTH = (DATA_WIDTH/8),
    parameter AVMM_ADDR_WIDTH = 36,
    parameter PIPELINE_OUTPUT = 0
)
(
    // ---- AXI-Lite 从机 (pcie_clk) ----
    input  wire                   clk,       // pcie_clk
    input  wire                   rst,
    input  wire [ADDR_WIDTH-1:0]  s_axil_awaddr,
    input  wire [2:0]             s_axil_awprot,
    input  wire                   s_axil_awvalid,
    output wire                   s_axil_awready,
    input  wire [DATA_WIDTH-1:0]  s_axil_wdata,
    input  wire [STRB_WIDTH-1:0]  s_axil_wstrb,
    input  wire                   s_axil_wvalid,
    output wire                   s_axil_wready,
    output wire [1:0]             s_axil_bresp,
    output wire                   s_axil_bvalid,
    input  wire                   s_axil_bready,
    input  wire [ADDR_WIDTH-1:0]  s_axil_araddr,
    input  wire [2:0]             s_axil_arprot,
    input  wire                   s_axil_arvalid,
    output wire                   s_axil_arready,
    output wire [DATA_WIDTH-1:0]  s_axil_rdata,
    output wire [1:0]             s_axil_rresp,
    output wire                   s_axil_rvalid,
    input  wire                   s_axil_rready,

    // ---- Avalon-MM 主口 (mem_clk = clk100M) ----
    input  wire                       mem_clk,
    output reg  [AVMM_ADDR_WIDTH-1:0] avm_address,
    output reg                        avm_read,
    output reg                        avm_write,
    output reg  [DATA_WIDTH-1:0]      avm_writedata,
    output reg  [STRB_WIDTH-1:0]      avm_byteenable,
    input  wire [DATA_WIDTH-1:0]      avm_readdata,
    input  wire                       avm_readdatavalid,
    input  wire                       avm_waitrequest,

    // ---- 状态 (mem_clk 域, 准静态) ----
    input  wire                   cal_ok0,
    input  wire                   cal_ok1
);
    // ---- 跨域寄存器 (握手载荷; pcie 域写, toggle 后 mem 域读, 稳定) ----
    reg [AVMM_ADDR_WIDTH-1:0] req_addr = 0;
    reg [DATA_WIDTH-1:0]      req_wdata = 0;
    reg [STRB_WIDTH-1:0]      req_be = 0;
    reg                       req_we = 0;
    reg                       req_tog = 0;      // pcie 域: 每次新请求翻转
    reg [DATA_WIDTH-1:0]      rsp_rdata = 0;    // mem 域写, pcie 域(done 后)读
    reg                       done_tog = 0;     // mem 域: 完成时翻转

    // =============== pcie_clk 域 ===============
    reg [18:0] page_reg = 0;             // am_address[35:17]

    // done_tog -> pcie 域同步
    (* srl_style="register" *) reg done_s1=0, done_s2=0, done_s3=0;
    always @(posedge clk) begin done_s1<=done_tog; done_s2<=done_s1; done_s3<=done_s2; end
    wire done_edge = (done_s2 ^ done_s3);
    // cal_ok 同步
    (* srl_style="register" *) reg c0a=0,c0b=0,c1a=0,c1b=0;
    always @(posedge clk) begin c0a<=cal_ok0; c0b<=c0a; c1a<=cal_ok1; c1b<=c1a; end

    localparam [1:0] P_IDLE=0, P_WAITB=1, P_WAITR=2;
    reg [1:0] pst = P_IDLE;
    reg awr=0, wr=0, bvld=0, arr=0, rvld=0;
    reg [DATA_WIDTH-1:0] rdata_reg=0;
    assign s_axil_awready=awr; assign s_axil_wready=wr;
    assign s_axil_bresp=2'b00; assign s_axil_bvalid=bvld;
    assign s_axil_arready=arr; assign s_axil_rresp=2'b00;
    assign s_axil_rdata=rdata_reg; assign s_axil_rvalid=rvld;

    wire wr_is_reg = s_axil_awaddr[17];
    wire rd_is_reg = s_axil_araddr[17];
    wire [3:0] wr_regidx = s_axil_awaddr[5:2];
    wire [3:0] rd_regidx = s_axil_araddr[5:2];
    wire [AVMM_ADDR_WIDTH-1:0] wr_avaddr = {page_reg, s_axil_awaddr[16:0]};
    wire [AVMM_ADDR_WIDTH-1:0] rd_avaddr = {page_reg, s_axil_araddr[16:0]};

    always @(posedge clk) begin
        awr<=0; wr<=0; arr<=0;
        if (bvld && s_axil_bready) bvld<=0;
        if (rvld && s_axil_rready) rvld<=0;

        case (pst)
            P_IDLE: begin
                if (s_axil_awvalid && s_axil_wvalid && !bvld && !rvld) begin
                    awr<=1; wr<=1;
                    if (wr_is_reg) begin
                        if (wr_regidx==4'd0) page_reg <= s_axil_wdata[18:0];
                        bvld<=1;
                    end else begin
                        req_addr<=wr_avaddr; req_wdata<=s_axil_wdata; req_be<=s_axil_wstrb;
                        req_we<=1'b1; req_tog<=~req_tog; pst<=P_WAITB;
                    end
                end else if (s_axil_arvalid && !rvld && !bvld) begin
                    arr<=1;
                    if (rd_is_reg) begin
                        case (rd_regidx)
                            4'd0: rdata_reg <= {13'd0, page_reg};
                            4'd1: rdata_reg <= {30'd0, c1b, c0b};
                            4'd3: rdata_reg <= 32'h44445242; // "DDRB"
                            default: rdata_reg <= 32'd0;
                        endcase
                        rvld<=1;
                    end else begin
                        req_addr<=rd_avaddr; req_we<=1'b0; req_be<=4'hF;
                        req_tog<=~req_tog; pst<=P_WAITR;
                    end
                end
            end
            P_WAITB: if (done_edge) begin bvld<=1; pst<=P_IDLE; end
            P_WAITR: if (done_edge) begin rdata_reg<=rsp_rdata; rvld<=1; pst<=P_IDLE; end
            default: pst<=P_IDLE;
        endcase

        if (rst) begin pst<=P_IDLE; awr<=0; wr<=0; bvld<=0; arr<=0; rvld<=0; end
    end

    // =============== mem_clk 域 ===============
    (* srl_style="register" *) reg req_s1=0, req_s2=0, req_s3=0;
    always @(posedge mem_clk) begin req_s1<=req_tog; req_s2<=req_s1; req_s3<=req_s2; end
    wire req_edge = (req_s2 ^ req_s3);

    localparam [1:0] M_IDLE=0, M_WR=1, M_RD=2, M_DONE=3;
    reg [1:0] mst = M_IDLE;

    always @(posedge mem_clk) begin
        avm_read<=1'b0; avm_write<=1'b0;
        case (mst)
            M_IDLE: if (req_edge) begin
                avm_address<=req_addr; avm_writedata<=req_wdata; avm_byteenable<=req_be;
                if (req_we) begin avm_write<=1'b1; mst<=M_WR; end
                else        begin avm_read <=1'b1; mst<=M_RD; end
            end
            M_WR: begin
                if (avm_waitrequest) avm_write<=1'b1;         // 保持到被接收
                else begin done_tog<=~done_tog; mst<=M_IDLE; end
            end
            M_RD: begin
                if (avm_waitrequest) avm_read<=1'b1;
                else mst<=M_DONE;                             // 命令已接收, 等 readdatavalid
            end
            M_DONE: if (avm_readdatavalid) begin
                rsp_rdata<=avm_readdata; done_tog<=~done_tog; mst<=M_IDLE;
            end
            default: mst<=M_IDLE;
        endcase
    end
endmodule
`resetall
