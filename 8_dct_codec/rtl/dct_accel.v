// =====================================================================
// MSA-2020 视频编解码变换核 —— dct_accel (8x8 2-D DCT / IDCT)
//   H.264 / H.265 / JPEG 共用的"变换心脏"。完整编解码器无法今夜从零写成
//   (运动估计+CABAC+去块滤波是巨型 IP);此核提供其数学核心, 可位精确验证。
//
//   AXI-Lite 从机 (与 video_accel/axil_ram 引脚兼容, 可直接替换)。
//   内存映射: addr[17:16] 00=寄存器 01=输入缓冲 10=输出缓冲。
//   每个 8x8 块占 64 个字, 行主序 (r*8+c)。输入/输出各 1 值/32-bit 字(有符号)。
//
//   寄存器:
//     0x00 CTRL   (W) bit0=start
//     0x04 STATUS (R) {magic 0x4443, ver, done, busy}
//     0x08 MODE   (RW) 0=正变换FDCT 1=反变换IDCT
//     0x14 COUNT  (RW) 8x8 块数 (<=256)
//     0x18 PARAM0 (RW) bit0=电平位移(FDCT输入-128 / IDCT输出+128并钳位0..255)
//     0x20 CHECKSUM(R) 输出 XOR
//     0x24 CYCLES  (R) 周期数
//     0x28 BLOCKS  (R) 已完成块数
//     0x3C ID      (R) 0x44435438 "DCT8"
//
//   定点: 系数 Q13(8192); 行变换后 >>8(四舍五入), 列变换后 >>18。见 gen_dct.py。
// =====================================================================
`resetall
`timescale 1ns / 1ps
`default_nettype none

module dct_accel #
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
    localparam BUF_AW = 14;
    localparam integer BUF_DEPTH = 1<<BUF_AW;

    (* ramstyle = "M20K" *) reg [31:0] in_mem  [0:BUF_DEPTH-1];
    (* ramstyle = "M20K" *) reg [31:0] out_mem [0:BUF_DEPTH-1];

    // 系数 ROM (Q13)
    reg signed [15:0] C [0:63];
    initial begin
        `include "dct_coef.vh"
    end

    reg [31:0] mode_reg=0, count_reg=0, param0_reg=0;
    reg [31:0] checksum_reg=0, cycles_reg=0, blocks_reg=0;
    reg        busy_reg=0, done_reg=0, start_pulse=0;
    wire       lshift = param0_reg[0];
    wire       is_idct = (mode_reg[0]);

    // ---------- AXI-Lite 写 ----------
    reg awr=0, wr=0, bvld=0;
    reg mem_wr_en;
    wire [1:0]        wr_region = s_axil_awaddr[17:16];
    wire [BUF_AW-1:0] wr_word   = s_axil_awaddr[BUF_AW+1:2];
    wire [3:0]        wr_regidx = s_axil_awaddr[5:2];
    assign s_axil_awready=awr; assign s_axil_wready=wr; assign s_axil_bresp=2'b00; assign s_axil_bvalid=bvld;
    reg awr_n, wr_n, bvld_n;
    always @* begin
        mem_wr_en=0; awr_n=0; wr_n=0; bvld_n = bvld && !s_axil_bready;
        if (s_axil_awvalid && s_axil_wvalid && (!bvld||s_axil_bready) && (!awr&&!wr)) begin
            awr_n=1; wr_n=1; bvld_n=1; mem_wr_en=1;
        end
    end
    integer bi;
    always @(posedge clk) begin
        awr<=awr_n; wr<=wr_n; bvld<=bvld_n; start_pulse<=0;
        if (mem_wr_en) begin
            if (wr_region==2'b01) begin
                for (bi=0;bi<4;bi=bi+1) if (s_axil_wstrb[bi]) in_mem[wr_word][8*bi+:8]<=s_axil_wdata[8*bi+:8];
            end else if (wr_region==2'b00) begin
                case (wr_regidx)
                    4'd0: start_pulse<=s_axil_wdata[0];
                    4'd2: mode_reg  <=s_axil_wdata;
                    4'd5: count_reg <=(s_axil_wdata>256)?256:s_axil_wdata;
                    4'd6: param0_reg<=s_axil_wdata;
                    default: ;
                endcase
            end
        end
        if (rst) begin awr<=0; wr<=0; bvld<=0; start_pulse<=0; end
    end

    // ---------- AXI-Lite 读 ----------
    reg arr=0, rvld=0; reg [31:0] rdata=0; reg mem_rd_en;
    wire [1:0]        rd_region = s_axil_araddr[17:16];
    wire [BUF_AW-1:0] rd_word   = s_axil_araddr[BUF_AW+1:2];
    wire [3:0]        rd_regidx = s_axil_araddr[5:2];
    reg [31:0] reg_rd;
    always @* begin
        case (rd_regidx)
            4'd1: reg_rd={16'h4443,8'h01,6'd0,done_reg,busy_reg};
            4'd2: reg_rd=mode_reg;
            4'd5: reg_rd=count_reg;
            4'd6: reg_rd=param0_reg;
            4'd8: reg_rd=checksum_reg;
            4'd9: reg_rd=cycles_reg;
            4'd10: reg_rd=blocks_reg;
            4'd15: reg_rd=32'h44435438; // "DCT8"
            default: reg_rd=32'd0;
        endcase
    end
    assign s_axil_arready=arr; assign s_axil_rdata=rdata; assign s_axil_rresp=2'b00; assign s_axil_rvalid=rvld;
    reg arr_n, rvld_n;
    always @* begin
        mem_rd_en=0; arr_n=0; rvld_n = rvld && !s_axil_rready;
        if (s_axil_arvalid && (!rvld||s_axil_rready) && !arr) begin arr_n=1; rvld_n=1; mem_rd_en=1; end
    end
    always @(posedge clk) begin
        arr<=arr_n; rvld<=rvld_n;
        if (mem_rd_en) begin
            case (rd_region)
                2'b00: rdata<=reg_rd;
                2'b01: rdata<=in_mem[rd_word];
                2'b10: rdata<=out_mem[rd_word];
                default: rdata<=32'hDEADBEEF;
            endcase
        end
        if (rst) begin arr<=0; rvld<=0; end
    end

    // ---------- 变换引擎 ----------
    // 计算侧 BRAM 端口
    reg [BUF_AW-1:0] ce_rd_addr=0; reg [31:0] ce_rd_data=0;
    reg [BUF_AW-1:0] ce_wr_addr=0; reg [31:0] ce_wr_data=0; reg ce_wr_en=0;
    always @(posedge clk) begin
        ce_rd_data <= in_mem[ce_rd_addr];
        if (ce_wr_en) out_mem[ce_wr_addr] <= ce_wr_data;
    end

    reg signed [31:0] blk  [0:63];   // 输入块
    reg signed [31:0] tbuf [0:63];   // 行变换结果 (转置缓冲)

    localparam [3:0] E_IDLE=0,E_LDA=1,E_LDC=2,E_ROW_RD=3,E_ROW_MAC=4,
                     E_COL_RD=5,E_COL_MAC=6,E_NEXT=7,E_DONE=8,E_LDW=9;
    reg [3:0] est = E_IDLE;
    reg [8:0] blkidx=0, nblk=0;          // 块索引/总数
    reg [BUF_AW-1:0] blk_base=0;
    reg [2:0] kk=0, mm=0, nn=0;          // 行/列/累加 计数
    reg [5:0] li=0;                      // 载入计数 0..63
    reg signed [63:0] acc=0;
    reg signed [31:0] a_r=0, x_r=0;      // 已寄存的操作数

    wire signed [63:0] prod = a_r * x_r;
    wire signed [63:0] nacc = acc + prod;
    wire signed [63:0] row_o = (nacc + 64'sd128)    >>> 8;    // S1
    wire signed [63:0] col_o = (nacc + 64'sd131072) >>> 18;   // S2
    // 列输出后处理 (IDCT 电平位移+钳位)
    wire signed [63:0] idct_px = col_o + (lshift ? 64'sd128 : 64'sd0);
    wire signed [31:0] col_final = is_idct ? (lshift ? ((idct_px<0)?32'sd0:(idct_px>255)?32'sd255:idct_px[31:0])
                                                      : col_o[31:0])
                                           : col_o[31:0];
    // 载入时的输入值 (FDCT 电平位移)
    wire signed [31:0] load_val = (!is_idct && lshift) ? ($signed({1'b0,ce_rd_data[15:0]}) - 32'sd128)
                                                       : $signed(ce_rd_data);
    // 当前抽头操作数 (组合选择, 下一拍寄存)
    wire signed [31:0] crow = is_idct ? $signed(C[nn*8+kk]) : $signed(C[kk*8+nn]);
    wire signed [31:0] xrow = blk[nn*8+mm];
    wire signed [31:0] ccol = is_idct ? $signed(C[nn*8+mm]) : $signed(C[mm*8+nn]);
    wire signed [31:0] xcol = tbuf[kk*8+nn];

    always @(posedge clk) begin
        ce_wr_en <= 1'b0;
        case (est)
            E_IDLE: if (start_pulse) begin
                busy_reg<=1; done_reg<=0; checksum_reg<=0; cycles_reg<=0; blocks_reg<=0;
                blkidx<=0; blk_base<=0; nblk<=count_reg[8:0];
                kk<=0; mm<=0; nn<=0; li<=0; acc<=0;
                if (count_reg==0) est<=E_DONE; else est<=E_LDA;
            end
            // ---- 载入 64 字 (BRAM 读延迟 1 拍: E_LDA->E_LDW->E_LDC) ----
            E_LDA: begin ce_rd_addr <= blk_base + li; cycles_reg<=cycles_reg+1; est<=E_LDW; end
            E_LDW: begin cycles_reg<=cycles_reg+1; est<=E_LDC; end
            E_LDC: begin
                blk[li] <= load_val;
                cycles_reg<=cycles_reg+1;
                if (li==6'd63) begin li<=0; kk<=0; mm<=0; nn<=0; acc<=0; est<=E_ROW_RD; end
                else begin li<=li+1'b1; est<=E_LDA; end
            end
            // ---- 行变换: tbuf[kk][mm] = (sum_nn crow*blk[nn][mm])>>S1 ----
            E_ROW_RD: begin a_r<=crow; x_r<=xrow; cycles_reg<=cycles_reg+1; est<=E_ROW_MAC; end
            E_ROW_MAC: begin
                cycles_reg<=cycles_reg+1;
                if (nn==3'd7) begin
                    tbuf[kk*8+mm] <= row_o[31:0];
                    acc<=0; nn<=0;
                    if (mm==3'd7) begin mm<=0;
                        if (kk==3'd7) begin kk<=0; est<=E_COL_RD; end
                        else kk<=kk+1'b1;
                    end else mm<=mm+1'b1;
                    est <= (mm==3'd7 && kk==3'd7) ? E_COL_RD : E_ROW_RD;
                end else begin
                    acc<=nacc; nn<=nn+1'b1; est<=E_ROW_RD;
                end
            end
            // ---- 列变换: out[kk][mm] = (sum_nn ccol*tbuf[kk][nn])>>S2 ----
            E_COL_RD: begin a_r<=ccol; x_r<=xcol; cycles_reg<=cycles_reg+1; est<=E_COL_MAC; end
            E_COL_MAC: begin
                cycles_reg<=cycles_reg+1;
                if (nn==3'd7) begin
                    ce_wr_addr <= blk_base + {kk,3'b000} + mm;   // kk*8+mm
                    ce_wr_data <= col_final;
                    ce_wr_en   <= 1'b1;
                    checksum_reg <= checksum_reg ^ col_final;
                    acc<=0; nn<=0;
                    if (mm==3'd7) begin mm<=0;
                        if (kk==3'd7) begin kk<=0; est<=E_NEXT; end
                        else kk<=kk+1'b1;
                    end else mm<=mm+1'b1;
                    est <= (mm==3'd7 && kk==3'd7) ? E_NEXT : E_COL_RD;
                end else begin
                    acc<=nacc; nn<=nn+1'b1; est<=E_COL_RD;
                end
            end
            E_NEXT: begin
                blocks_reg <= blocks_reg + 1;
                if (blkidx+1 >= nblk) est<=E_DONE;
                else begin blkidx<=blkidx+1'b1; blk_base<=blk_base+7'd64; li<=0; kk<=0; mm<=0; nn<=0; acc<=0; est<=E_LDA; end
            end
            E_DONE: begin busy_reg<=0; done_reg<=1; est<=E_IDLE; end
            default: est<=E_IDLE;
        endcase
        if (rst) begin est<=E_IDLE; busy_reg<=0; done_reg<=0; ce_wr_en<=0; end
    end
endmodule
`resetall
