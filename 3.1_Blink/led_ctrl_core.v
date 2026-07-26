// led_ctrl_core -- 寄存器组 + LED 灯效引擎 (Avalon-MM 从机)
// MSA-2020 (A-2020) 板卡, 由 JTAG-Avalon 桥经 System Console 控制
//
// 寄存器映射 (字节地址, 32bit 寄存器):
//   0x00  ID      RO  固定 0xA2020001, 用于上位机识别
//   0x04  CTRL    RW  [2:0] 模式: 0=自动轮换 1=计数器闪烁 2=流水灯
//                              3=呼吸灯 4=波浪呼吸 5=手动直控
//   0x08  MANUAL  RW  [8:0] 手动模式下的 LED 电平
//   0x0C  SPEED   RW  [2:0] 速度档位 0~5, 每档速度 x2 (默认 0)
//   0x10  STATUS  RO  [2:0] CTRL 回读 | [6:4] 当前生效灯效 | [24:16] LED 实时值
//   0x14  PHASE   RO  相位计数器实时值 (读数在变 = 板卡活着)
module led_ctrl_core (
    input  wire        clk,
    // Avalon-MM slave (固定 1 拍读延迟, 不需要等待)
    input  wire [31:0] av_address,      // 字节地址
    input  wire        av_read,
    input  wire        av_write,
    input  wire [31:0] av_writedata,
    output reg  [31:0] av_readdata,
    output reg         av_readdatavalid,
    output wire        av_waitrequest,
    // ISSP 备用控制通道 (bit15=1 时接管控制)
    //   source: [2:0] 模式 | [11:3] 手动LED | [14:12] 速度 | [15] 接管使能
    //   probe : [8:0] LED | [11:9] 灯效 | [14:12] 模式 | [15] issp接管
    //           [19:16] 心跳 | [31:24] 签名 0x5A
    input  wire [15:0] issp_source,
    output wire [31:0] issp_probe,
    // 板卡 LED
    output wire [8:0]  LED
);

parameter ACTIVE_LOW = 1'b0;
localparam [31:0] ID_CODE = 32'hA202_0001;

assign av_waitrequest = 1'b0;

//---------------------------------------------------------------
// 控制寄存器
//---------------------------------------------------------------
reg [2:0] ctrl_mode  = 3'd0;    // 上电默认: 自动轮换
reg [8:0] manual_led = 9'd0;
reg [2:0] speed      = 3'd0;

wire [2:0] addr_w = av_address[4:2];    // 字地址

always @(posedge clk) begin
    if (av_write) begin
        case (addr_w)
            3'd1: ctrl_mode  <= (av_writedata[2:0] > 3'd5) ? 3'd5
                                                           : av_writedata[2:0];
            3'd2: manual_led <= av_writedata[8:0];
            3'd3: speed      <= (av_writedata[2:0] > 3'd5) ? 3'd5
                                                           : av_writedata[2:0];
            default: ;
        endcase
    end
end

//---------------------------------------------------------------
// ISSP 通道同步与控制选择 (ISSP 写入来自 JTAG 时钟域, 打两拍同步)
//---------------------------------------------------------------
reg [15:0] issp_s1 = 16'd0, issp_s2 = 16'd0;
always @(posedge clk) begin
    issp_s1 <= issp_source;
    issp_s2 <= issp_s1;
end

wire       use_issp   = issp_s2[15];
wire [2:0] eff_mode   = use_issp ? ((issp_s2[2:0] > 3'd5) ? 3'd5 : issp_s2[2:0])
                                 : ctrl_mode;
wire [8:0] eff_manual = use_issp ? issp_s2[11:3] : manual_led;
wire [2:0] eff_speed  = use_issp ? ((issp_s2[14:12] > 3'd5) ? 3'd5 : issp_s2[14:12])
                                 : speed;

//---------------------------------------------------------------
// 相位累加器: 所有灯效的时基, 速度档位每 +1 整体加速一倍
//---------------------------------------------------------------
reg [30:0] phase = 31'd0;
always @(posedge clk)
    phase <= phase + (31'd1 << eff_speed);

//---------------------------------------------------------------
// 4 种灯效 (与 led_show 相同)
//---------------------------------------------------------------
// 计数器闪烁
wire [8:0] pat_blink = phase[28:20];

// 来回流水灯
reg [3:0] pos = 4'd0;
reg       dir = 1'b0;
wire      step = (phase[22:0] == 23'd0);
always @(posedge clk) begin
    if (step) begin
        if (!dir) begin
            if (pos == 4'd8) begin dir <= 1'b1; pos <= 4'd7; end
            else             pos <= pos + 4'd1;
        end else begin
            if (pos == 4'd0) begin dir <= 1'b0; pos <= 4'd1; end
            else             pos <= pos - 4'd1;
        end
    end
end
wire [8:0] pat_scan = 9'b1 << pos;

// 呼吸灯
wire [15:0] breath_lvl = phase[26] ? ~phase[25:10] : phase[25:10];
wire        breath_on  = (phase[15:0] < breath_lvl);
wire [8:0]  pat_breath = {9{breath_on}};

// 波浪呼吸
wire [8:0] pat_wave;
genvar i;
generate
    for (i = 0; i < 9; i = i + 1) begin : wave
        wire [15:0] ph     = phase[25:10] + i * 16'd6553;
        wire [14:0] bright = ph[15] ? ~ph[14:0] : ph[14:0];
        assign pat_wave[i] = (phase[14:0] < bright);
    end
endgenerate

//---------------------------------------------------------------
// 灯效选择: 自动轮换时用 phase 高位切换, 否则按 CTRL 指定
//---------------------------------------------------------------
// sel: 0=闪烁 1=流水 2=呼吸 3=波浪 4=手动
wire [2:0] sel = (eff_mode == 3'd0) ? {1'b0, phase[30:29]} :
                 (eff_mode == 3'd5) ? 3'd4 :
                                      eff_mode - 3'd1;

reg [8:0] led_r = 9'd0;
always @(posedge clk) begin
    case (sel)
        3'd0:    led_r <= pat_blink;
        3'd1:    led_r <= pat_scan;
        3'd2:    led_r <= pat_breath;
        3'd3:    led_r <= pat_wave;
        default: led_r <= eff_manual;
    endcase
end

assign LED = ACTIVE_LOW ? ~led_r : led_r;

assign issp_probe = {8'h5A, 4'd0, phase[27:24], use_issp, eff_mode, sel, led_r};

//---------------------------------------------------------------
// 读通道: 固定 1 拍延迟
//---------------------------------------------------------------
always @(posedge clk) begin
    av_readdatavalid <= av_read;
    case (addr_w)
        3'd0:    av_readdata <= ID_CODE;
        3'd1:    av_readdata <= {29'd0, ctrl_mode};
        3'd2:    av_readdata <= {23'd0, manual_led};
        3'd3:    av_readdata <= {29'd0, speed};
        3'd4:    av_readdata <= {7'd0, led_r, 9'd0, sel, 1'b0, eff_mode};
        3'd5:    av_readdata <= {1'b0, phase};
        default: av_readdata <= 32'hDEAD_BEEF;
    endcase
end

endmodule
