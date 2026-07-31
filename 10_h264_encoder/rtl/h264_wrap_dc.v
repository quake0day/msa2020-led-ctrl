// =====================================================================
// H.264 编码器 PCIe-BAR 外壳 —— 双时钟版 (h264_wrap_dc)
//   把 host 面 (AXI-Lite / 配置寄存器 / 输入缓冲写 / 输出缓冲读) 放在 pclk(pcie_clk),
//   编码器 (xk264+ext+喂帧+抓码流+控制FSM) 放在 eclk(enc_clk 50MHz)。
//   跨域用: ①双时钟真双口 BRAM(输入: pclk写/eclk读; 输出: eclk写/pclk读, 时间上分离
//   —— host 先写满输入再 start, done 后才读输出, 同址不同时) ②start 用 toggle 跨到 eclk
//   ③busy/done 电平 2FF 同步回 pclk ④bytes/rinc 在 done 跨沿采进 pclk 保持寄存器。
//   —— 取代原 axil_cdc(多bit异步握手 + set_clock_groups async), 证明性正确, 消除
//   marginal-hold/未约束跨域这一整类物理风险。编码器侧逻辑与已验证的 h264_wrap 逐字一致。
//
//   BAR0 (256KB): addr[17:16]=00 寄存器 / 01 输入帧缓冲 / 10 输出码流缓冲
//   寄存器(idx=addr[5:2]): 0x00 CTRL(bit0=start) 0x04 STATUS(bit0=busy bit1=done [31:16]=0x4832)
//     0x08 QP 0x0C FLAGS(bit0=mode bit1=intra) 0x10 XTOTAL 0x14 YTOTAL 0x18 BYTES 0x1C RINC 0x3C ID
// =====================================================================
`resetall
`timescale 1ns / 1ps
`default_nettype none

module h264_wrap_dc #
(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 18,
    parameter STRB_WIDTH = (DATA_WIDTH/8)
)
(
    // ---- host 面 (pcie_clk) ----
    input  wire                   pclk,
    input  wire                   prst,
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
    // ---- 编码器面 (enc_clk) ----
    input  wire                   eclk,
    input  wire                   erst
);
    localparam IN_AW  = 13;   // 8192 x 64-bit 输入缓冲
    localparam OUT_AW = 14;   // 16384 x 32-bit 输出缓冲

    // 双时钟真双口 BRAM: 端口A(pclk)=host, 端口B(eclk)=编码器
    (* ramstyle="M20K" *) reg [63:0] in_bram  [0:(1<<IN_AW)-1];
    (* ramstyle="M20K" *) reg [31:0] out_bram [0:(1<<OUT_AW)-1];

    // ============================================================
    //  pclk 域: 寄存器 + AXI-Lite + in_bram 写端口 + out_bram 读端口
    // ============================================================
    reg [5:0]  qp_reg = 6'd27;
    reg        mode_reg = 1'b0, intra_reg = 1'b1;
    reg [7:0]  xtotal_reg = 0, ytotal_reg = 0;
    reg        start_tog_p = 1'b0;     // start 跨域 toggle

    // ---- AXI-Lite 写 ----
    reg awr=0, wr=0, bvld=0, mem_wr; reg awr_n,wr_n,bvld_n;
    wire [1:0]        wr_region = s_axil_awaddr[17:16];
    wire [IN_AW-1:0]  wr_entry  = s_axil_awaddr[IN_AW+2:3];
    wire              wr_half   = s_axil_awaddr[2];
    wire [3:0]        wr_regidx = s_axil_awaddr[5:2];
    assign s_axil_awready=awr; assign s_axil_wready=wr; assign s_axil_bresp=2'b00; assign s_axil_bvalid=bvld;
    always @* begin
        mem_wr=0; awr_n=0; wr_n=0; bvld_n = bvld && !s_axil_bready;
        if (s_axil_awvalid && s_axil_wvalid && (!bvld||s_axil_bready) && (!awr&&!wr)) begin
            awr_n=1; wr_n=1; bvld_n=1; mem_wr=1;
        end
    end
    always @(posedge pclk) begin
        awr<=awr_n; wr<=wr_n; bvld<=bvld_n;
        if (mem_wr) begin
            if (wr_region==2'b01) begin
                if (wr_half==1'b0) in_bram[wr_entry][63:32] <= s_axil_wdata; // 偶字->高
                else               in_bram[wr_entry][31:0]  <= s_axil_wdata; // 奇字->低
            end else if (wr_region==2'b00) begin
                case (wr_regidx)
                    4'd0: if (s_axil_wdata[0]) start_tog_p <= ~start_tog_p;  // 触发 -> 翻转
                    4'd2: qp_reg      <= s_axil_wdata[5:0];
                    4'd3: begin mode_reg<=s_axil_wdata[0]; intra_reg<=s_axil_wdata[1]; end
                    4'd4: xtotal_reg  <= s_axil_wdata[7:0];
                    4'd5: ytotal_reg  <= s_axil_wdata[7:0];
                    default: ;
                endcase
            end
        end
        if (prst) begin awr<=0; wr<=0; bvld<=0; start_tog_p<=0; end
    end

    // ---- eclk->pclk 同步: busy/done 电平, bytes/rinc + 诊断校验和 保持 ----
    wire        busy_e, done_e;             // 编码器域产生
    wire [31:0] bytes_e, rinc_e, in_sum_e, in_xor_e, out_sum_e;
    wire [31:0] pre_sum_e, res_sum_e, rec_sum_e;
    reg  b1=0,b2=0,d1=0,d2=0,d2_q=0;
    reg  [31:0] bytes_hold=0, rinc_hold=0, in_sum_hold=0, in_xor_hold=0, out_sum_hold=0;
    reg  [31:0] pre_sum_hold=0, res_sum_hold=0, rec_sum_hold=0;
    always @(posedge pclk) begin
        b1<=busy_e; b2<=b1; d1<=done_e; d2<=d1; d2_q<=d2;
        if (d2 && !d2_q) begin // done 跨沿采(此时都已稳定)
            bytes_hold<=bytes_e; rinc_hold<=rinc_e;
            in_sum_hold<=in_sum_e; in_xor_hold<=in_xor_e; out_sum_hold<=out_sum_e;
            pre_sum_hold<=pre_sum_e; res_sum_hold<=res_sum_e; rec_sum_hold<=rec_sum_e;
        end
        if (prst) begin b1<=0;b2<=0;d1<=0;d2<=0;d2_q<=0; bytes_hold<=0; rinc_hold<=0;
                        in_sum_hold<=0; in_xor_hold<=0; out_sum_hold<=0;
                        pre_sum_hold<=0; res_sum_hold<=0; rec_sum_hold<=0; end
    end

    // ---- AXI-Lite 读 ----
    reg arr=0, rvld=0; reg [31:0] rdata=0; reg mem_rd; reg arr_n,rvld_n;
    wire [1:0]         rd_region = s_axil_araddr[17:16];
    wire [OUT_AW-1:0]  rd_oword  = s_axil_araddr[OUT_AW+1:2];
    wire [3:0]         rd_regidx = s_axil_araddr[5:2];
    reg [31:0] reg_rd;
    always @* begin
        case (rd_regidx)
            4'd1: reg_rd={16'h4832,14'd0,d2,b2};    // STATUS (同步过的 done/busy)
            4'd2: reg_rd={26'd0,qp_reg};
            4'd3: reg_rd={30'd0,intra_reg,mode_reg};
            4'd4: reg_rd={24'd0,xtotal_reg};
            4'd5: reg_rd={24'd0,ytotal_reg};
            4'd6: reg_rd=bytes_hold;
            4'd7: reg_rd=rinc_hold;
            4'd8: reg_rd=in_sum_hold;    // 0x20 诊断: 交付给编码器的输入数据求和
            4'd9: reg_rd=in_xor_hold;    // 0x24 诊断: 输入数据异或签名
            4'd10:reg_rd=out_sum_hold;   // 0x28 诊断: 输出码流字节求和(内容签名)
            4'd11:reg_rd=pre_sum_hold;   // 0x2C 诊断: tq 帧内预测输入签名
            4'd12:reg_rd=res_sum_hold;   // 0x30 诊断: tq 变换量化残差签名
            4'd13:reg_rd=rec_sum_hold;   // 0x34 诊断: tq 重建像素签名
            4'd15: reg_rd=32'h48323634; // "H264"
            default: reg_rd=32'd0;
        endcase
    end
    assign s_axil_arready=arr; assign s_axil_rdata=rdata; assign s_axil_rresp=2'b00; assign s_axil_rvalid=rvld;
    always @* begin
        mem_rd=0; arr_n=0; rvld_n = rvld && !s_axil_rready;
        if (s_axil_arvalid && (!rvld||s_axil_rready) && !arr) begin arr_n=1; rvld_n=1; mem_rd=1; end
    end
    always @(posedge pclk) begin
        arr<=arr_n; rvld<=rvld_n;
        if (mem_rd) begin
            case (rd_region)
                2'b00: rdata<=reg_rd;
                2'b10: rdata<=out_bram[rd_oword];   // 输出码流(pclk 读端口)
                default: rdata<=32'd0;              // 输入回读诊断已撤(输入交付已证 2304/2304)
            endcase
        end
        if (prst) begin arr<=0; rvld<=0; end
    end

    // ============================================================
    //  跨域: start toggle(pclk) -> eclk 脉冲; 配置快照
    // ============================================================
    reg st1=0, st2=0, st3=0;
    always @(posedge eclk) begin
        st1<=start_tog_p; st2<=st1; st3<=st2;
        if (erst) begin st1<=0; st2<=0; st3<=0; end
    end
    wire start_e = st2 ^ st3;   // eclk 1拍启动脉冲

    reg [5:0] qp_e=6'd27; reg mode_e=0, intra_e=1; reg [7:0] xtotal_e=0, ytotal_e=0;
    always @(posedge eclk) begin
        if (start_e) begin
            qp_e<=qp_reg; mode_e<=mode_reg; intra_e<=intra_reg;
            xtotal_e<=xtotal_reg; ytotal_e<=ytotal_reg;   // 配置准静态(start前早已稳定), 快照进 eclk
        end
        if (erst) begin qp_e<=6'd27; mode_e<=0; intra_e<=1; xtotal_e<=0; ytotal_e<=0; end
    end

    // ============================================================
    //  eclk 域: xk264 + ext_ + 喂帧 + 抓码流 + 控制FSM
    //  (逻辑与已验证 h264_wrap 逐字一致, 仅 clk->eclk / start_pulse->start_e / 配置->_e)
    // ============================================================
    wire        rst_n = ~erst;
    wire        sys_done, enc_ld_start; wire [7:0] enc_ld_x, enc_ld_y;
    reg         sys_start_r=0;
    reg  [63:0] rdata_i_r=0; reg rvalid_i_r=0; wire rinc_o;
    wire        winc_o; wire [7:0] wdata_o;
    wire        ext_start, ext_done, ext_wen, ext_ren; wire [2:0] ext_mode;
    wire [7:0]  ext_mb_x, ext_mb_y; wire [3:0] ext_addr; wire [127:0] ext_data_i, ext_data_o;
    wire [31:0] dbg_pre, dbg_res, dbg_rec; wire dbg_val;   // tq阶段诊断 tap

    top u_top (
        .clk(eclk), .rst_n(rst_n),
        .sys_start(sys_start_r), .sys_done(sys_done), .sys_intra_flag(intra_e),
        .sys_qp(qp_e), .sys_mode(mode_e), .sys_x_total(xtotal_e), .sys_y_total(ytotal_e),
        .enc_ld_start(enc_ld_start), .enc_ld_x(enc_ld_x), .enc_ld_y(enc_ld_y),
        .rdata_i(rdata_i_r), .rvalid_i(rvalid_i_r), .rinc_o(rinc_o),
        .wdata_o(wdata_o), .wfull_i(1'b0), .winc_o(winc_o),
        .ext_mb_x_o(ext_mb_x), .ext_mb_y_o(ext_mb_y), .ext_start_o(ext_start),
        .ext_done_i(ext_done), .ext_mode_o(ext_mode), .ext_wen_i(ext_wen), .ext_ren_i(ext_ren),
        .ext_addr_i(ext_addr), .ext_data_i(ext_data_i), .ext_data_o(ext_data_o),
        .dbg_pre(dbg_pre), .dbg_res(dbg_res), .dbg_rec(dbg_rec), .dbg_val(dbg_val)
    );
    // tq阶段三段签名累加(dbg_val 有效时): pre=帧内预测 res=变换量化 rec=重建
    reg [31:0] pre_sum_reg=0, res_sum_reg=0, rec_sum_reg=0;
    always @(posedge eclk) begin
        if (start_e) begin pre_sum_reg<=0; res_sum_reg<=0; rec_sum_reg<=0; end
        else if (dbg_val) begin
            pre_sum_reg <= pre_sum_reg + dbg_pre;
            res_sum_reg <= res_sum_reg + dbg_res;
            rec_sum_reg <= rec_sum_reg + dbg_rec;
        end
        if (erst) begin pre_sum_reg<=0; res_sum_reg<=0; rec_sum_reg<=0; end
    end
    wire [7:0] mb_x_total = xtotal_e + 8'd1;
    h264_ext_mem #(.MAX_MBS(512)) u_ext (
        .clk(eclk), .rst_n(rst_n), .frame_parity(1'b0), .mb_x_total(mb_x_total),
        .ext_start(ext_start), .ext_mode(ext_mode), .ext_mb_x(ext_mb_x), .ext_mb_y(ext_mb_y),
        .ext_data_o(ext_data_o),
        .ext_done(ext_done), .ext_wen(ext_wen), .ext_ren(ext_ren), .ext_addr(ext_addr),
        .ext_data_i(ext_data_i)
    );

    // ---- 输入喂帧 (in_bram eclk 读端口, 48 字/MB burst) ----
    reg [IN_AW-1:0] feed_addr = 0; reg [5:0] feed_cnt = 0;
    always @(posedge eclk) begin
        if (start_e) begin feed_addr<=0; rdata_i_r<=0; rvalid_i_r<=0; end
        else if (rinc_o && feed_cnt!=6'd48) begin
            rdata_i_r <= in_bram[feed_addr]; rvalid_i_r <= 1'b1; feed_addr <= feed_addr + 1'b1;
        end else begin rdata_i_r<=0; rvalid_i_r<=0; end
        if (erst) begin feed_addr<=0; rvalid_i_r<=0; end
    end
    always @(posedge eclk) begin
        if (rinc_o) feed_cnt<=feed_cnt+1'b1; else feed_cnt<=0;
        if (erst) feed_cnt<=0;
    end
    reg [31:0] rinc_cnt_reg = 0;
    always @(posedge eclk) begin
        if (start_e) rinc_cnt_reg<=0;
        else if (rinc_o) rinc_cnt_reg<=rinc_cnt_reg+1'b1;
        if (erst) rinc_cnt_reg<=0;
    end

    // ---- 诊断校验和: 交付给编码器的输入 (rdata_i_r/rvalid_i_r) + 输出码流 (wdata_o/winc_o) ----
    reg [31:0] in_sum_reg=0, in_xor_reg=0, out_sum_reg=0;
    always @(posedge eclk) begin
        if (start_e) begin in_sum_reg<=0; in_xor_reg<=0; end
        else if (rvalid_i_r) begin
            in_sum_reg <= in_sum_reg + rdata_i_r[31:0] + rdata_i_r[63:32];
            in_xor_reg <= in_xor_reg ^ rdata_i_r[31:0] ^ rdata_i_r[63:32];
        end
        if (erst) begin in_sum_reg<=0; in_xor_reg<=0; end
    end
    always @(posedge eclk) begin
        if (start_e) out_sum_reg<=0;
        else if (winc_o) out_sum_reg <= out_sum_reg + wdata_o;
        if (erst) out_sum_reg<=0;
    end

    // ---- 抓码流 (4 字节攒 1 字写 out_bram eclk 写端口) ----
    reg flush_word=0;   // 声明提前(严格 LRM: 先声明后使用; Questa 拒绝 use-before-declare)
    reg [31:0] bytes_reg = 0;
    reg [31:0] wacc = 0;
    always @(posedge eclk) begin
        if (start_e) bytes_reg<=0;
        else if (winc_o) begin
            case (bytes_reg[1:0])
                2'd0: wacc[7:0]   <= wdata_o;
                2'd1: wacc[15:8]  <= wdata_o;
                2'd2: wacc[23:16] <= wdata_o;
                2'd3: out_bram[bytes_reg[OUT_AW+1:2]] <= {wdata_o, wacc[23:0]};
            endcase
            bytes_reg <= bytes_reg + 1'b1;
        end
        if (flush_word) out_bram[bytes_reg[OUT_AW+1:2]] <= wacc;
        if (erst) bytes_reg<=0;
    end

    // ---- 控制 FSM ----
    reg busy_reg = 0, done_reg = 0;
    localparam C_IDLE=0, C_START=1, C_BUSY=2, C_DONE_WAIT=3, C_FLUSH=4;
    reg [2:0] cst = C_IDLE;
    always @(posedge eclk) begin
        sys_start_r<=1'b0; flush_word<=1'b0;
        case (cst)
            C_IDLE: if (start_e) begin busy_reg<=1'b1; done_reg<=1'b0; sys_start_r<=1'b1; cst<=C_START; end
            C_START: cst<=C_BUSY;                          // 让 sys_done 落 0
            C_BUSY: if (sys_done==1'b0) cst<=C_DONE_WAIT;  // 已进入编码
            C_DONE_WAIT: if (sys_done==1'b1) begin
                            if (bytes_reg[1:0]!=2'd0) flush_word<=1'b1;  // 残字收尾
                            cst<=C_FLUSH;
                         end
            C_FLUSH: begin busy_reg<=1'b0; done_reg<=1'b1; cst<=C_IDLE; end
            default: cst<=C_IDLE;
        endcase
        if (erst) begin cst<=C_IDLE; busy_reg<=0; done_reg<=0; sys_start_r<=0; end
    end

    assign busy_e  = busy_reg;
    assign done_e  = done_reg;
    assign bytes_e = bytes_reg;
    assign rinc_e  = rinc_cnt_reg;
    assign in_sum_e  = in_sum_reg;
    assign in_xor_e  = in_xor_reg;
    assign out_sum_e = out_sum_reg;
    assign pre_sum_e = pre_sum_reg;
    assign res_sum_e = res_sum_reg;
    assign rec_sum_e = rec_sum_reg;
endmodule
`resetall
