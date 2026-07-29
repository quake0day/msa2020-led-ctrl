// =====================================================================
// MSA-2020 视频计算加速器 —— video_accel
//   AXI-Lite 从机(与 axil_ram 引脚完全兼容,可直接替换)。
//   host 通过 BAR0 写入一帧像素 -> 选模式 -> 触发 -> 读回结果。
//
//   内存映射 (18-bit 字节地址, 32-bit 字, 256KB BAR):
//     addr[17:16]==2'b00 -> 寄存器区 (idx = addr[5:2])
//     addr[17:16]==2'b01 -> 输入缓冲 in_mem  0x10000..0x1FFFF (16K 字/64KB)
//     addr[17:16]==2'b10 -> 输出缓冲 out_mem 0x20000..0x2FFFF (16K 字/64KB)
//
//   像素格式: 32-bit = {8'X, R[23:16], G[15:8], B[7:0]}  (0RGB)
//
//   寄存器:
//     0x00 CTRL   (W)  bit0=start(触发计算)
//     0x04 STATUS (R)  {magic 0x5641, ver 0x01, done, busy}
//     0x08 MODE   (RW) 0=passthrough 1=RGB->YUV 2=YUV->RGB 3=gray
//                      4=invert 5=AI-normalize 6=threshold 7=bright/contrast
//     0x0C WIDTH  (RW) 图像宽(像素)
//     0x10 HEIGHT (RW) 图像高
//     0x14 COUNT  (RW) 处理的像素(字)个数, <=16384
//     0x18 PARAM0 (RW) 依模式: normalize均值{_,mR,mG,mB} / threshold阈值 / 亮度
//     0x1C PARAM1 (RW) 依模式: normalize尺度 / 对比度
//     0x20 CHECKSUM (R) 所有输出字的 XOR (免读全缓冲即可校验)
//     0x24 CYCLES   (R) 计算耗时(时钟周期)
//     0x28 PIXELS   (R) 已处理像素数
//     0x3C ID       (R) 0x56414343 "VACC"
// =====================================================================
`resetall
`timescale 1ns / 1ps
`default_nettype none

module video_accel #
(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 18,
    parameter STRB_WIDTH = (DATA_WIDTH/8),
    parameter PIPELINE_OUTPUT = 0   // 兼容 axil_ram 参数(此处忽略)
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

    localparam BUF_AW = 14;               // 16384 字 = 64KB 缓冲
    localparam integer BUF_DEPTH = 1<<BUF_AW;

    // ---- 双端口 BRAM ----
    (* ramstyle = "M20K" *) reg [31:0] in_mem  [0:BUF_DEPTH-1];
    (* ramstyle = "M20K" *) reg [31:0] out_mem [0:BUF_DEPTH-1];

    // ---- 寄存器 ----
    reg [31:0] mode_reg   = 32'd0;
    reg [31:0] width_reg  = 32'd0;
    reg [31:0] height_reg = 32'd0;
    reg [31:0] count_reg  = 32'd0;
    reg [31:0] param0_reg = 32'd0;
    reg [31:0] param1_reg = 32'd0;
    reg [31:0] param2_reg = 32'd0;   // conv 系数 c4..c7 / c8+shift
    reg [31:0] param3_reg = 32'd0;   // conv: bit0=取绝对值(边缘检测)
    reg [31:0] checksum_reg = 32'd0;
    reg [31:0] cycles_reg   = 32'd0;
    reg [31:0] pixels_reg    = 32'd0;

    reg        busy_reg = 1'b0;
    reg        done_reg = 1'b0;
    reg        start_pulse = 1'b0;

    // =================================================================
    // AXI-Lite 写通道 (仿 axil_ram 的握手, 单拍接收, bvalid 次拍)
    // =================================================================
    reg s_axil_awready_reg = 1'b0, s_axil_awready_next;
    reg s_axil_wready_reg  = 1'b0, s_axil_wready_next;
    reg s_axil_bvalid_reg  = 1'b0, s_axil_bvalid_next;

    wire [1:0]        wr_region  = s_axil_awaddr[17:16];
    wire [BUF_AW-1:0] wr_word    = s_axil_awaddr[BUF_AW+1:2];
    wire [3:0]        wr_regidx  = s_axil_awaddr[5:2];
    reg               mem_wr_en;

    assign s_axil_awready = s_axil_awready_reg;
    assign s_axil_wready  = s_axil_wready_reg;
    assign s_axil_bresp   = 2'b00;
    assign s_axil_bvalid  = s_axil_bvalid_reg;

    always @* begin
        mem_wr_en = 1'b0;
        s_axil_awready_next = 1'b0;
        s_axil_wready_next  = 1'b0;
        s_axil_bvalid_next  = s_axil_bvalid_reg && !s_axil_bready;

        if (s_axil_awvalid && s_axil_wvalid && (!s_axil_bvalid || s_axil_bready) &&
            (!s_axil_awready && !s_axil_wready)) begin
            s_axil_awready_next = 1'b1;
            s_axil_wready_next  = 1'b1;
            s_axil_bvalid_next  = 1'b1;
            mem_wr_en           = 1'b1;
        end
    end

    integer bi;
    always @(posedge clk) begin
        s_axil_awready_reg <= s_axil_awready_next;
        s_axil_wready_reg  <= s_axil_wready_next;
        s_axil_bvalid_reg  <= s_axil_bvalid_next;

        start_pulse <= 1'b0;

        if (mem_wr_en) begin
            if (wr_region == 2'b01) begin
                // 写输入缓冲(按字节使能)
                for (bi = 0; bi < 4; bi = bi + 1)
                    if (s_axil_wstrb[bi])
                        in_mem[wr_word][8*bi +: 8] <= s_axil_wdata[8*bi +: 8];
            end else if (wr_region == 2'b00) begin
                // 写寄存器
                case (wr_regidx)
                    4'd0: start_pulse <= s_axil_wdata[0];
                    4'd2: mode_reg    <= s_axil_wdata;
                    4'd3: width_reg   <= s_axil_wdata;
                    4'd4: height_reg  <= s_axil_wdata;
                    4'd5: count_reg   <= (s_axil_wdata > BUF_DEPTH) ? BUF_DEPTH : s_axil_wdata;
                    4'd6:  param0_reg <= s_axil_wdata;
                    4'd7:  param1_reg <= s_axil_wdata;
                    4'd11: param2_reg <= s_axil_wdata;  // 0x2C
                    4'd12: param3_reg <= s_axil_wdata;  // 0x30
                    default: ;
                endcase
            end
            // wr_region==2'b10 (输出区) host 写忽略
        end

        if (rst) begin
            s_axil_awready_reg <= 1'b0;
            s_axil_wready_reg  <= 1'b0;
            s_axil_bvalid_reg  <= 1'b0;
            start_pulse        <= 1'b0;
        end
    end

    // =================================================================
    // AXI-Lite 读通道
    // =================================================================
    reg s_axil_arready_reg = 1'b0, s_axil_arready_next;
    reg s_axil_rvalid_reg  = 1'b0, s_axil_rvalid_next;
    reg [31:0] s_axil_rdata_reg = 32'd0;
    reg        mem_rd_en;

    wire [1:0]        rd_region = s_axil_araddr[17:16];
    wire [BUF_AW-1:0] rd_word   = s_axil_araddr[BUF_AW+1:2];
    wire [3:0]        rd_regidx = s_axil_araddr[5:2];

    // 寄存器读多路
    reg [31:0] reg_rd_comb;
    always @* begin
        case (rd_regidx)
            4'd0:  reg_rd_comb = 32'd0;
            4'd1:  reg_rd_comb = {16'h5641, 8'h01, 6'd0, done_reg, busy_reg};
            4'd2:  reg_rd_comb = mode_reg;
            4'd3:  reg_rd_comb = width_reg;
            4'd4:  reg_rd_comb = height_reg;
            4'd5:  reg_rd_comb = count_reg;
            4'd6:  reg_rd_comb = param0_reg;
            4'd7:  reg_rd_comb = param1_reg;
            4'd8:  reg_rd_comb = checksum_reg;
            4'd9:  reg_rd_comb = cycles_reg;
            4'd10: reg_rd_comb = pixels_reg;
            4'd11: reg_rd_comb = param2_reg;
            4'd12: reg_rd_comb = param3_reg;
            4'd15: reg_rd_comb = 32'h56414343; // "VACC"
            default: reg_rd_comb = 32'd0;
        endcase
    end

    assign s_axil_arready = s_axil_arready_reg;
    assign s_axil_rdata   = s_axil_rdata_reg;
    assign s_axil_rresp   = 2'b00;
    assign s_axil_rvalid  = s_axil_rvalid_reg;

    always @* begin
        mem_rd_en = 1'b0;
        s_axil_arready_next = 1'b0;
        s_axil_rvalid_next  = s_axil_rvalid_reg && !s_axil_rready;

        if (s_axil_arvalid && (!s_axil_rvalid || s_axil_rready) && !s_axil_arready) begin
            s_axil_arready_next = 1'b1;
            s_axil_rvalid_next  = 1'b1;
            mem_rd_en           = 1'b1;
        end
    end

    always @(posedge clk) begin
        s_axil_arready_reg <= s_axil_arready_next;
        s_axil_rvalid_reg  <= s_axil_rvalid_next;

        if (mem_rd_en) begin
            case (rd_region)
                2'b00:   s_axil_rdata_reg <= reg_rd_comb;
                2'b01:   s_axil_rdata_reg <= in_mem[rd_word];
                2'b10:   s_axil_rdata_reg <= out_mem[rd_word];
                default: s_axil_rdata_reg <= 32'hDEADBEEF;
            endcase
        end

        if (rst) begin
            s_axil_arready_reg <= 1'b0;
            s_axil_rvalid_reg  <= 1'b0;
        end
    end

    // =================================================================
    // 计算引擎
    //   点运算模式(0-7): 每像素 4 拍 ISSUE->CAPTURE->WRITE->ADVANCE
    //   卷积模式(8): 每输出像素采集 3x3 邻域 (CV_*), 边界钳位复制
    // =================================================================
    localparam [3:0] S_IDLE=4'd0, S_ISSUE=4'd1, S_CAPTURE=4'd2,
                     S_WRITE=4'd3, S_ADVANCE=4'd4, S_DONE=4'd5,
                     S_CV_SETUP=4'd6, S_CV_ADDR=4'd7, S_CV_WAIT=4'd8,
                     S_CV_ACC=4'd9, S_CV_WRITE=4'd10, S_CV_ADVANCE=4'd11,
                     S_WAIT=4'd12;
    reg [3:0]        state = S_IDLE;
    reg [BUF_AW-1:0] idx = 0;
    reg [31:0]       nproc = 0;             // 本次要处理的像素数

    // ---- 卷积(mode 8) 状态 ----
    wire             is_conv = (mode_reg[3:0] == 4'd8);
    reg [BUF_AW-1:0] px_x = 0, px_y = 0;    // 当前输出像素坐标
    reg [3:0]        tap = 0;               // 3x3 抽头 0..8
    reg signed [31:0] cv_acc = 0;
    reg [BUF_AW-1:0] base_m = 0, base_0 = 0, base_p = 0; // 上/中/下 行基址
    reg [BUF_AW-1:0] col_m = 0, col_0 = 0, col_p = 0;    // 左/中/右 列
    wire [BUF_AW-1:0] cw = width_reg[BUF_AW-1:0];
    wire [BUF_AW-1:0] ch = height_reg[BUF_AW-1:0];
    wire [BUF_AW-1:0] cv_ym1 = (px_y == 0)      ? px_y : (px_y - 1'b1);
    wire [BUF_AW-1:0] cv_yp1 = (px_y+1 >= ch)   ? px_y : (px_y + 1'b1);
    wire [BUF_AW-1:0] cv_xm1 = (px_x == 0)      ? px_x : (px_x - 1'b1);
    wire [BUF_AW-1:0] cv_xp1 = (px_x+1 >= cw)   ? px_x : (px_x + 1'b1);
    // 当前抽头的行基址/列(组合)
    reg [BUF_AW-1:0] cv_rowbase, cv_col;
    always @* begin
        case (tap)
            4'd0: begin cv_rowbase=base_m; cv_col=col_m; end
            4'd1: begin cv_rowbase=base_m; cv_col=col_0; end
            4'd2: begin cv_rowbase=base_m; cv_col=col_p; end
            4'd3: begin cv_rowbase=base_0; cv_col=col_m; end
            4'd4: begin cv_rowbase=base_0; cv_col=col_0; end
            4'd5: begin cv_rowbase=base_0; cv_col=col_p; end
            4'd6: begin cv_rowbase=base_p; cv_col=col_m; end
            4'd7: begin cv_rowbase=base_p; cv_col=col_0; end
            4'd8: begin cv_rowbase=base_p; cv_col=col_p; end
            default: begin cv_rowbase=base_0; cv_col=col_0; end
        endcase
    end
    wire [BUF_AW-1:0] cv_neighbor = cv_rowbase + cv_col;
    // 当前抽头系数 (有符号 int8)
    reg signed [7:0] ccoef;
    always @* begin
        case (tap)
            4'd0: ccoef = param0_reg[7:0];
            4'd1: ccoef = param0_reg[15:8];
            4'd2: ccoef = param0_reg[23:16];
            4'd3: ccoef = param0_reg[31:24];
            4'd4: ccoef = param1_reg[7:0];
            4'd5: ccoef = param1_reg[15:8];
            4'd6: ccoef = param1_reg[23:16];
            4'd7: ccoef = param1_reg[31:24];
            4'd8: ccoef = param2_reg[7:0];
            default: ccoef = 8'sd0;
        endcase
    end
    wire [4:0]        cv_shift = param2_reg[12:8];        // 归一化右移量
    wire              cv_abs   = param3_reg[0];           // 取绝对值(边缘)
    wire signed [31:0] cv_shifted = cv_abs ? ((cv_acc[31] ? -cv_acc : cv_acc) >>> cv_shift)
                                           : (cv_acc >>> cv_shift);
    wire [7:0]        cv_out = clip8(cv_shifted);

    reg [BUF_AW-1:0] ce_rd_addr = 0;        // 计算侧读 in_mem
    reg [31:0]       ce_rd_data = 0;
    reg [BUF_AW-1:0] ce_wr_addr = 0;        // 计算侧写 out_mem
    reg [31:0]       ce_wr_data = 0;
    reg              ce_wr_en   = 1'b0;
    reg [31:0]       result_reg = 0;

    // BRAM 计算端口 (端口 B): in_mem 读, out_mem 写
    always @(posedge clk) begin
        ce_rd_data <= in_mem[ce_rd_addr];
        if (ce_wr_en) out_mem[ce_wr_addr] <= ce_wr_data;
    end

    // ---- 组合像素运算 ----
    function [7:0] clip8;
        input signed [31:0] v;
        clip8 = (v < 0) ? 8'd0 : (v > 255) ? 8'd255 : v[7:0];
    endfunction
    function [7:0] clip8s;   // 有符号饱和到 int8, 以补码字节返回
        input signed [31:0] v;
        clip8s = (v < -128) ? 8'sd128 : (v > 127) ? 8'sd127 : v[7:0];
    endfunction

    wire signed [31:0] R = $signed({24'd0, ce_rd_data[23:16]});
    wire signed [31:0] G = $signed({24'd0, ce_rd_data[15:8]});
    wire signed [31:0] B = $signed({24'd0, ce_rd_data[7:0]});
    // YUV 解读 (mode2)
    wire signed [31:0] Yc = $signed({24'd0, ce_rd_data[23:16]});
    wire signed [31:0] Uc = $signed({24'd0, ce_rd_data[15:8]});
    wire signed [31:0] Vc = $signed({24'd0, ce_rd_data[7:0]});

    wire [7:0] luma = clip8((77*R + 150*G + 29*B) >>> 8);

    // normalize 参数
    wire signed [31:0] mR = $signed({24'd0, param0_reg[23:16]});
    wire signed [31:0] mG = $signed({24'd0, param0_reg[15:8]});
    wire signed [31:0] mB = $signed({24'd0, param0_reg[7:0]});
    wire signed [31:0] nscale = $signed({24'd0, param1_reg[7:0]}); // Q0.8

    // bright/contrast 参数
    wire signed [31:0] contrast = $signed({24'd0, param1_reg[7:0]}); // Q2.6
    wire signed [31:0] bright   = $signed({{24{param0_reg[7]}}, param0_reg[7:0]}); // int8

    reg [31:0] comp;
    always @* begin
        case (mode_reg[3:0])
            4'd0: comp = ce_rd_data;                              // passthrough
            4'd1: comp = {8'h00,                                  // RGB->YUV BT.601
                          clip8((77*R + 150*G + 29*B) >>> 8),
                          clip8(((-43*R - 85*G + 128*B) >>> 8) + 128),
                          clip8(((128*R - 107*G - 21*B) >>> 8) + 128)};
            4'd2: comp = {8'h00,                                  // YUV->RGB BT.601
                          clip8(Yc + ((359*(Vc-128)) >>> 8)),
                          clip8(Yc - ((88*(Uc-128) + 183*(Vc-128)) >>> 8)),
                          clip8(Yc + ((454*(Uc-128)) >>> 8))};
            4'd3: comp = {8'h00, luma, luma, luma};               // grayscale
            4'd4: comp = {ce_rd_data[31:24], ~ce_rd_data[23:0]};  // invert RGB
            4'd5: comp = {8'h00,                                  // AI normalize -> int8
                          clip8s(((R-mR)*nscale) >>> 8),
                          clip8s(((G-mG)*nscale) >>> 8),
                          clip8s(((B-mB)*nscale) >>> 8)};
            4'd6: comp = (luma >= param0_reg[7:0]) ? 32'h00FFFFFF : 32'h00000000; // threshold
            4'd7: comp = {8'h00,                                  // bright/contrast
                          clip8(((R*contrast) >>> 6) + bright),
                          clip8(((G*contrast) >>> 6) + bright),
                          clip8(((B*contrast) >>> 6) + bright)};
            default: comp = ce_rd_data;
        endcase
    end

    always @(posedge clk) begin
        ce_wr_en <= 1'b0;

        case (state)
            S_IDLE: begin
                if (start_pulse) begin
                    busy_reg   <= 1'b1;
                    done_reg   <= 1'b0;
                    idx        <= 0;
                    px_x       <= 0;
                    px_y       <= 0;
                    tap        <= 0;
                    cv_acc     <= 0;
                    nproc      <= (count_reg == 0) ? 0 : count_reg;
                    checksum_reg <= 32'd0;
                    cycles_reg   <= 32'd0;
                    pixels_reg   <= 32'd0;
                    if (count_reg == 0)   state <= S_DONE;
                    else if (is_conv)     state <= S_CV_SETUP;
                    else                  state <= S_ISSUE;
                end
            end
            S_ISSUE: begin
                ce_rd_addr <= idx;      // 提交 in_mem 读地址
                cycles_reg <= cycles_reg + 1;
                state      <= S_WAIT;
            end
            S_WAIT: begin               // BRAM 读延迟 1 拍, 此后 ce_rd_data 才有效
                cycles_reg <= cycles_reg + 1;
                state      <= S_CAPTURE;
            end
            S_CAPTURE: begin
                result_reg <= comp;     // ce_rd_data 此刻有效, comp 组合算出
                cycles_reg <= cycles_reg + 1;
                state      <= S_WRITE;
            end
            S_WRITE: begin
                ce_wr_addr <= idx;
                ce_wr_data <= result_reg;
                ce_wr_en   <= 1'b1;
                checksum_reg <= checksum_reg ^ result_reg;
                pixels_reg   <= pixels_reg + 1;
                cycles_reg   <= cycles_reg + 1;
                state        <= S_ADVANCE;
            end
            S_ADVANCE: begin
                cycles_reg <= cycles_reg + 1;
                if (idx + 1 >= nproc) begin
                    state <= S_DONE;
                end else begin
                    idx   <= idx + 1;
                    state <= S_ISSUE;
                end
            end

            // ---- 卷积路径 (mode 8): 采集 3x3 邻域, MAC, 归一化 ----
            S_CV_SETUP: begin
                base_m <= cv_ym1 * cw;
                base_0 <= px_y   * cw;
                base_p <= cv_yp1 * cw;
                col_m  <= cv_xm1;
                col_0  <= px_x;
                col_p  <= cv_xp1;
                tap    <= 0;
                cv_acc <= 0;
                cycles_reg <= cycles_reg + 1;
                state  <= S_CV_ADDR;
            end
            S_CV_ADDR: begin
                ce_rd_addr <= cv_neighbor;   // 提交邻域读地址
                cycles_reg <= cycles_reg + 1;
                state      <= S_CV_WAIT;
            end
            S_CV_WAIT: begin                 // BRAM 读延迟
                cycles_reg <= cycles_reg + 1;
                state      <= S_CV_ACC;
            end
            S_CV_ACC: begin                  // ce_rd_data 有效, 累加 coef*luma
                cv_acc     <= cv_acc + ccoef * $signed({1'b0, luma});
                cycles_reg <= cycles_reg + 1;
                if (tap == 4'd8) state <= S_CV_WRITE;
                else begin tap <= tap + 1'b1; state <= S_CV_ADDR; end
            end
            S_CV_WRITE: begin
                ce_wr_addr   <= idx;
                ce_wr_data   <= {8'h00, cv_out, cv_out, cv_out};
                ce_wr_en     <= 1'b1;
                checksum_reg <= checksum_reg ^ {8'h00, cv_out, cv_out, cv_out};
                pixels_reg   <= pixels_reg + 1;
                cycles_reg   <= cycles_reg + 1;
                state        <= S_CV_ADVANCE;
            end
            S_CV_ADVANCE: begin
                cycles_reg <= cycles_reg + 1;
                if (idx + 1 >= nproc) begin
                    state <= S_DONE;
                end else begin
                    idx <= idx + 1'b1;
                    if (px_x + 1 >= cw) begin px_x <= 0; px_y <= px_y + 1'b1; end
                    else                     px_x <= px_x + 1'b1;
                    state <= S_CV_SETUP;
                end
            end

            S_DONE: begin
                busy_reg <= 1'b0;
                done_reg <= 1'b1;
                state    <= S_IDLE;
            end
            default: state <= S_IDLE;
        endcase

        if (rst) begin
            state    <= S_IDLE;
            busy_reg <= 1'b0;
            done_reg <= 1'b0;
            ce_wr_en <= 1'b0;
        end
    end

endmodule

`resetall
