// led_ctrl -- 顶层: JTAG-Avalon 桥 + 寄存器/灯效核心
// 电脑端经板载 USB-Blaster (FT232H) -> JTAG -> Avalon-MM 读写寄存器控制 LED
module led_ctrl (
    input  wire       clk100M,
    output wire [8:0] LED
);

// JTAG to Avalon Master Bridge (Platform Designer 生成, 见 jtag_sys.qsys)
wire [31:0] av_address;
wire        av_read, av_write;
wire [31:0] av_writedata, av_readdata;
wire        av_waitrequest, av_readdatavalid;
wire [3:0]  av_byteenable;

// S10 配置未完全结束前 ninit_done 为高, 用它复位 JTAG 桥,
// 防止桥内状态机在器件初始化期间带损坏状态启动 (Critical Warning 20615)
wire ninit_done;
wire [15:0] issp_source;
wire [31:0] issp_probe;

jtag_sys u_jtag (
    .clk_clk               (clk100M),
    .reset_reset           (ninit_done),
    .ninit_done_ninit_done (ninit_done),
    .issp_sources_source   (issp_source),
    .issp_probes_probe     (issp_probe),
    .master_address        (av_address),
    .master_read           (av_read),
    .master_write          (av_write),
    .master_writedata      (av_writedata),
    .master_readdata       (av_readdata),
    .master_waitrequest    (av_waitrequest),
    .master_readdatavalid  (av_readdatavalid),
    .master_byteenable     (av_byteenable),
    .master_reset_reset    ()
);

led_ctrl_core u_core (
    .clk              (clk100M),
    .av_address       (av_address),
    .av_read          (av_read),
    .av_write         (av_write),
    .av_writedata     (av_writedata),
    .av_readdata      (av_readdata),
    .av_readdatavalid (av_readdatavalid),
    .av_waitrequest   (av_waitrequest),
    .issp_source      (issp_source),
    .issp_probe       (issp_probe),
    .LED              (LED)
);

endmodule
