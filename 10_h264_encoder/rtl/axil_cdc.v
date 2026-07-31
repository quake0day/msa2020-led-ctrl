// =====================================================================
// AXI-Lite 跨时钟桥 (axil_cdc): 主侧(pcie_clk) <-> 从侧(enc_clk)
//   单发 + toggle 握手。用于把 H.264 编码器放到较慢的 enc_clk 上跑 (满足时序),
//   同时 host 的 BAR 访问仍在 pcie_clk。从侧再接 h264_wrap。
// =====================================================================
`resetall
`timescale 1ns / 1ps
`default_nettype none

module axil_cdc #
(
    parameter ADDR_WIDTH = 18,
    parameter DATA_WIDTH = 32,
    parameter STRB_WIDTH = (DATA_WIDTH/8)
)
(
    // ---- 上游 (pcie_clk): 作 AXI-Lite 从机, 接 pcie_axil_master ----
    input  wire                   s_clk,
    input  wire                   s_rst,
    input  wire [ADDR_WIDTH-1:0]  s_awaddr,  input wire [2:0] s_awprot,
    input  wire                   s_awvalid, output wire s_awready,
    input  wire [DATA_WIDTH-1:0]  s_wdata,   input wire [STRB_WIDTH-1:0] s_wstrb,
    input  wire                   s_wvalid,  output wire s_wready,
    output wire [1:0]             s_bresp,   output wire s_bvalid, input wire s_bready,
    input  wire [ADDR_WIDTH-1:0]  s_araddr,  input wire [2:0] s_arprot,
    input  wire                   s_arvalid, output wire s_arready,
    output wire [DATA_WIDTH-1:0]  s_rdata,   output wire [1:0] s_rresp,
    output wire                   s_rvalid,  input wire s_rready,
    // ---- 下游 (enc_clk): 作 AXI-Lite 主机, 接 h264_wrap ----
    input  wire                   m_clk,
    input  wire                   m_rst,
    output reg  [ADDR_WIDTH-1:0]  m_awaddr,  output wire [2:0] m_awprot,
    output reg                    m_awvalid, input wire m_awready,
    output reg  [DATA_WIDTH-1:0]  m_wdata,   output reg [STRB_WIDTH-1:0] m_wstrb,
    output reg                    m_wvalid,  input wire m_wready,
    input  wire [1:0]             m_bresp,   input wire m_bvalid, output reg m_bready,
    output reg  [ADDR_WIDTH-1:0]  m_araddr,  output wire [2:0] m_arprot,
    output reg                    m_arvalid, input wire m_arready,
    input  wire [DATA_WIDTH-1:0]  m_rdata,   input wire [1:0] m_rresp,
    input  wire                   m_rvalid,  output reg m_rready
);
    assign m_awprot=3'd0; assign m_arprot=3'd0;

    // 请求载荷 (s 域写, toggle 后 m 域读)
    reg                    req_is_wr;
    reg [ADDR_WIDTH-1:0]   req_addr;
    reg [DATA_WIDTH-1:0]   req_wdata;
    reg [STRB_WIDTH-1:0]   req_wstrb;
    reg                    req_tog=0;
    reg [DATA_WIDTH-1:0]   rsp_rdata;
    reg                    done_tog=0;

    // ---- s 域 ----
    (* srl_style="register" *) reg d1=0,d2=0,d3=0;
    always @(posedge s_clk) begin d1<=done_tog; d2<=d1; d3<=d2; end
    wire done_edge = d2^d3;
    localparam S_IDLE=0,S_WB=1,S_RB=2; reg [1:0] sst=S_IDLE;
    reg sawr=0,swr=0,sbv=0,sarr=0,srv=0; reg [DATA_WIDTH-1:0] srdata=0;
    assign s_awready=sawr; assign s_wready=swr; assign s_bresp=2'b00; assign s_bvalid=sbv;
    assign s_arready=sarr; assign s_rresp=2'b00; assign s_rdata=srdata; assign s_rvalid=srv;
    always @(posedge s_clk) begin
        sawr<=0; swr<=0; sarr<=0;
        if (sbv&&s_bready) sbv<=0;
        if (srv&&s_rready) srv<=0;
        case (sst)
            S_IDLE: begin
                if (s_awvalid&&s_wvalid&&!sbv&&!srv) begin
                    sawr<=1; swr<=1; req_is_wr<=1; req_addr<=s_awaddr; req_wdata<=s_wdata;
                    req_wstrb<=s_wstrb; req_tog<=~req_tog; sst<=S_WB;
                end else if (s_arvalid&&!srv&&!sbv) begin
                    sarr<=1; req_is_wr<=0; req_addr<=s_araddr; req_tog<=~req_tog; sst<=S_RB;
                end
            end
            S_WB: if (done_edge) begin sbv<=1; sst<=S_IDLE; end
            S_RB: if (done_edge) begin srdata<=rsp_rdata; srv<=1; sst<=S_IDLE; end
        endcase
        if (s_rst) begin sst<=S_IDLE; sawr<=0; swr<=0; sbv<=0; sarr<=0; srv<=0; end
    end

    // ---- m 域 ----
    (* srl_style="register" *) reg r1=0,r2=0,r3=0;
    always @(posedge m_clk) begin r1<=req_tog; r2<=r1; r3<=r2; end
    wire req_edge = r2^r3;
    localparam M_IDLE=0,M_AW=1,M_AR=2,M_B=3,M_R=4; reg [2:0] mst=M_IDLE;
    always @(posedge m_clk) begin
        case (mst)
            M_IDLE: if (req_edge) begin
                if (req_is_wr) begin
                    m_awaddr<=req_addr; m_wdata<=req_wdata; m_wstrb<=req_wstrb;
                    m_awvalid<=1; m_wvalid<=1; m_bready<=1; mst<=M_AW;
                end else begin
                    m_araddr<=req_addr; m_arvalid<=1; m_rready<=1; mst<=M_AR;
                end
            end
            M_AW: begin
                if (m_awready) m_awvalid<=0;
                if (m_wready)  m_wvalid<=0;
                mst<=M_B;
            end
            M_B: if (m_bvalid) begin m_bready<=0; done_tog<=~done_tog; mst<=M_IDLE; end
            M_AR: begin if (m_arready) m_arvalid<=0; mst<=M_R; end
            M_R: if (m_rvalid) begin rsp_rdata<=m_rdata; m_rready<=0; done_tog<=~done_tog; mst<=M_IDLE; end
        endcase
        if (m_rst) begin mst<=M_IDLE; m_awvalid<=0; m_wvalid<=0; m_bready<=0; m_arvalid<=0; m_rready<=0; end
    end
endmodule
`resetall
