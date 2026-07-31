// =====================================================================
// H.264 编码器 PCIe-BAR 外壳 (h264_wrap)
//   AXI-Lite 从机 (与 video_accel 引脚兼容, 可作 PCIe BAR 后端)。
//   host 写 MB-tiled YUV 到输入缓冲 -> 设寄存器 -> 触发 -> xk264 编码 ->
//   winc_o 码流抓进输出缓冲 -> host 读回 + 字节数; 再软件 h264_pack.py 打包成 .264。
//   ext_ 参考帧走片上 h264_ext_mem (中小分辨率免 DDR)。全在 pcie_clk 单时钟域。
//
//   BAR0 (256KB):
//     addr[17:16]=00 寄存器  01 输入帧缓冲(0x10000)  10 输出码流缓冲(0x20000)
//   寄存器 (idx=addr[5:2]):
//     0x00 CTRL   W bit0=start
//     0x04 STATUS R bit0=busy bit1=done [31:16]=0x4832
//     0x08 QP     RW sys_qp[5:0]
//     0x0C FLAGS  RW bit0=sys_mode bit1=sys_intra_flag
//     0x10 XTOTAL RW sys_x_total (帧宽MB-1)
//     0x14 YTOTAL RW sys_y_total (帧高MB-1)
//     0x18 BYTES  R  码流字节数
//     0x3C ID     R  0x48323634 "H264"
// =====================================================================
`resetall
`timescale 1ns / 1ps
`default_nettype none

module h264_wrap #
(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 18,
    parameter STRB_WIDTH = (DATA_WIDTH/8),
    parameter PIPELINE_OUTPUT = 0
)
(
    input  wire                   clk,
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
    input  wire                   s_axil_rready
);
    wire rst_n = ~rst;
    localparam IN_AW  = 13;   // 8192 x 64-bit 输入缓冲 (~170 MB @48 字/MB)
    localparam OUT_AW = 14;   // 16384 x 32-bit 输出缓冲 (64KB 码流)

    (* ramstyle="M20K" *) reg [63:0] in_bram  [0:(1<<IN_AW)-1];
    (* ramstyle="M20K" *) reg [31:0] out_bram [0:(1<<OUT_AW)-1];

    // ---- 寄存器 ----
    reg [5:0]  qp_reg = 6'd27;
    reg        mode_reg = 1'b0, intra_reg = 1'b1;
    reg [7:0]  xtotal_reg = 0, ytotal_reg = 0;
    reg [31:0] bytes_reg = 0;
    reg        busy_reg = 0, done_reg = 0, start_pulse = 0;

    // ================= AXI-Lite 写 =================
    reg awr=0, wr=0, bvld=0, mem_wr; reg awr_n,wr_n,bvld_n;
    wire [1:0]        wr_region = s_axil_awaddr[17:16];
    wire [IN_AW-1:0]  wr_entry  = s_axil_awaddr[IN_AW+2:3]; // 输入 64-bit entry
    wire              wr_half   = s_axil_awaddr[2];         // 0=偶字(高32) 1=奇字(低32)
    wire [3:0]        wr_regidx = s_axil_awaddr[5:2];
    assign s_axil_awready=awr; assign s_axil_wready=wr; assign s_axil_bresp=2'b00; assign s_axil_bvalid=bvld;
    always @* begin
        mem_wr=0; awr_n=0; wr_n=0; bvld_n = bvld && !s_axil_bready;
        if (s_axil_awvalid && s_axil_wvalid && (!bvld||s_axil_bready) && (!awr&&!wr)) begin
            awr_n=1; wr_n=1; bvld_n=1; mem_wr=1;
        end
    end
    always @(posedge clk) begin
        awr<=awr_n; wr<=wr_n; bvld<=bvld_n; start_pulse<=1'b0;
        if (mem_wr) begin
            if (wr_region==2'b01) begin
                if (wr_half==1'b0) in_bram[wr_entry][63:32] <= s_axil_wdata; // 偶字->高
                else               in_bram[wr_entry][31:0]  <= s_axil_wdata; // 奇字->低
            end else if (wr_region==2'b00) begin
                case (wr_regidx)
                    4'd0: start_pulse <= s_axil_wdata[0];
                    4'd2: qp_reg      <= s_axil_wdata[5:0];
                    4'd3: begin mode_reg<=s_axil_wdata[0]; intra_reg<=s_axil_wdata[1]; end
                    4'd4: xtotal_reg  <= s_axil_wdata[7:0];
                    4'd5: ytotal_reg  <= s_axil_wdata[7:0];
                    default: ;
                endcase
            end
        end
        if (rst) begin awr<=0; wr<=0; bvld<=0; start_pulse<=0; end
    end

    // ================= AXI-Lite 读 =================
    reg arr=0, rvld=0; reg [31:0] rdata=0; reg mem_rd; reg arr_n,rvld_n;
    wire [1:0]         rd_region = s_axil_araddr[17:16];
    wire [OUT_AW-1:0]  rd_oword  = s_axil_araddr[OUT_AW+1:2];
    wire [3:0]         rd_regidx = s_axil_araddr[5:2];
    reg [31:0] rinc_cnt_reg = 0;   // 诊断: 编码器请求输入的次数
    reg [31:0] reg_rd;
    always @* begin
        case (rd_regidx)
            4'd1: reg_rd={16'h4832,14'd0,done_reg,busy_reg};
            4'd2: reg_rd={26'd0,qp_reg};
            4'd3: reg_rd={30'd0,intra_reg,mode_reg};
            4'd4: reg_rd={24'd0,xtotal_reg};
            4'd5: reg_rd={24'd0,ytotal_reg};
            4'd6: reg_rd=bytes_reg;
            4'd7: reg_rd=rinc_cnt_reg;   // 诊断: rinc 计数
            4'd15: reg_rd=32'h48323634; // "H264"
            default: reg_rd=32'd0;
        endcase
    end
    // 输入缓冲回读 (region 01): 诊断 host 写进去的帧是否正确
    wire [IN_AW-1:0] rd_entry = s_axil_araddr[IN_AW+2:3];
    wire             rd_half  = s_axil_araddr[2];
    assign s_axil_arready=arr; assign s_axil_rdata=rdata; assign s_axil_rresp=2'b00; assign s_axil_rvalid=rvld;
    always @* begin
        mem_rd=0; arr_n=0; rvld_n = rvld && !s_axil_rready;
        if (s_axil_arvalid && (!rvld||s_axil_rready) && !arr) begin arr_n=1; rvld_n=1; mem_rd=1; end
    end
    always @(posedge clk) begin
        arr<=arr_n; rvld<=rvld_n;
        if (mem_rd) begin
            case (rd_region)
                2'b00: rdata<=reg_rd;
                2'b01: rdata<= rd_half ? in_bram[rd_entry][31:0] : in_bram[rd_entry][63:32];
                2'b10: rdata<=out_bram[rd_oword];
                default: rdata<=32'hDEADBEEF;
            endcase
        end
        if (rst) begin arr<=0; rvld<=0; end
    end

    // ================= xk264 编码器 + ext_ 控制器 =================
    wire        sys_done, enc_ld_start; wire [7:0] enc_ld_x, enc_ld_y;
    reg         sys_start_r=0;
    reg  [63:0] rdata_i_r=0; reg rvalid_i_r=0; wire rinc_o;
    wire        winc_o; wire [7:0] wdata_o;
    wire        ext_start, ext_done, ext_wen, ext_ren; wire [2:0] ext_mode;
    wire [7:0]  ext_mb_x, ext_mb_y; wire [3:0] ext_addr; wire [127:0] ext_data_i, ext_data_o;

    top u_top (
        .clk(clk), .rst_n(rst_n),
        .sys_start(sys_start_r), .sys_done(sys_done), .sys_intra_flag(intra_reg),
        .sys_qp(qp_reg), .sys_mode(mode_reg), .sys_x_total(xtotal_reg), .sys_y_total(ytotal_reg),
        .enc_ld_start(enc_ld_start), .enc_ld_x(enc_ld_x), .enc_ld_y(enc_ld_y),
        .rdata_i(rdata_i_r), .rvalid_i(rvalid_i_r), .rinc_o(rinc_o),
        .wdata_o(wdata_o), .wfull_i(1'b0), .winc_o(winc_o),
        .ext_mb_x_o(ext_mb_x), .ext_mb_y_o(ext_mb_y), .ext_start_o(ext_start),
        .ext_done_i(ext_done), .ext_mode_o(ext_mode), .ext_wen_i(ext_wen), .ext_ren_i(ext_ren),
        .ext_addr_i(ext_addr), .ext_data_i(ext_data_i), .ext_data_o(ext_data_o)
    );
    wire [7:0] mb_x_total = xtotal_reg + 8'd1;
    h264_ext_mem #(.MAX_MBS(512)) u_ext (
        .clk(clk), .rst_n(rst_n), .frame_parity(1'b0), .mb_x_total(mb_x_total),
        .ext_start(ext_start), .ext_mode(ext_mode), .ext_mb_x(ext_mb_x), .ext_mb_y(ext_mb_y),
        .ext_data_o(ext_data_o),
        .ext_done(ext_done), .ext_wen(ext_wen), .ext_ren(ext_ren), .ext_addr(ext_addr),
        .ext_data_i(ext_data_i)
    );

    // ---- 输入喂帧 (镜像仿真: 48 字/MB burst) ----
    reg [IN_AW-1:0] feed_addr = 0; reg [5:0] feed_cnt = 0;
    always @(posedge clk) begin
        if (start_pulse) begin feed_addr<=0; rdata_i_r<=0; rvalid_i_r<=0; end
        else if (rinc_o && feed_cnt!=6'd48) begin
            rdata_i_r <= in_bram[feed_addr]; rvalid_i_r <= 1'b1; feed_addr <= feed_addr + 1'b1;
        end else begin rdata_i_r<=0; rvalid_i_r<=0; end
        if (rst) begin feed_addr<=0; rvalid_i_r<=0; end
    end
    always @(posedge clk) begin
        if (rinc_o) feed_cnt<=feed_cnt+1'b1; else feed_cnt<=0;
        if (rst) feed_cnt<=0;
    end
    always @(posedge clk) begin
        if (start_pulse) rinc_cnt_reg<=0;
        else if (rinc_o) rinc_cnt_reg<=rinc_cnt_reg+1'b1;
        if (rst) rinc_cnt_reg<=0;
    end

    // ---- 抓码流 (4 字节攒 1 字写出) ----
    reg [31:0] wacc = 0;
    always @(posedge clk) begin
        if (start_pulse) bytes_reg<=0;
        else if (winc_o) begin
            case (bytes_reg[1:0])
                2'd0: wacc[7:0]   <= wdata_o;
                2'd1: wacc[15:8]  <= wdata_o;
                2'd2: wacc[23:16] <= wdata_o;
                2'd3: out_bram[bytes_reg[OUT_AW+1:2]] <= {wdata_o, wacc[23:0]};
            endcase
            bytes_reg <= bytes_reg + 1'b1;
        end
        // 收尾: done 时若不足整字, 补写残字 (只在 flush 拍)
        if (flush_word) out_bram[bytes_reg[OUT_AW+1:2]] <= wacc;
    end

    // ---- 控制 FSM ----
    localparam C_IDLE=0, C_START=1, C_BUSY=2, C_DONE_WAIT=3, C_FLUSH=4;
    reg [2:0] cst = C_IDLE; reg flush_word=0;
    always @(posedge clk) begin
        sys_start_r<=1'b0; flush_word<=1'b0;
        case (cst)
            C_IDLE: if (start_pulse) begin busy_reg<=1'b1; done_reg<=1'b0; sys_start_r<=1'b1; cst<=C_START; end
            C_START: cst<=C_BUSY;                          // 让 sys_done 落 0
            C_BUSY: if (sys_done==1'b0) cst<=C_DONE_WAIT;  // 已进入编码
            C_DONE_WAIT: if (sys_done==1'b1) begin
                            if (bytes_reg[1:0]!=2'd0) flush_word<=1'b1;  // 残字收尾
                            cst<=C_FLUSH;
                         end
            C_FLUSH: begin busy_reg<=1'b0; done_reg<=1'b1; cst<=C_IDLE; end
            default: cst<=C_IDLE;
        endcase
        if (rst) begin cst<=C_IDLE; busy_reg<=0; done_reg<=0; sys_start_r<=0; end
    end
endmodule
`resetall
