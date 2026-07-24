// led_ctrl -- 单通道 DDR4 诊断版 (丝印 DIMM0)
// 按公开参考设计修正: PAR/ALERT 启用并连接, 时序由 IP 推导 (TCL18/WTCL12),
// DM on / DBI off / ECC off 64bit。cal_debug 经 ISSP 可读校准报告,
// 板级 I2C (AC28/AB28) 可读内存条 SPD。
module led_ctrl (
    input  wire       clk100M,
    output wire [8:0] LED,
    // 板级 I2C (SPD / FPC202 / retimer 共享总线)
    inout  wire        i2c_scl,
    inout  wire        i2c_sda,
    // DDR4 通道 (丝印 DIMM0)
    input  wire        ddr4_0_ref_clk, ddr4_0_rzqin,
    output wire [16:0] ddr4_0_a,
    output wire        ddr4_0_act_n,
    output wire [1:0]  ddr4_0_ba, ddr4_0_bg,
    output wire        ddr4_0_ck, ddr4_0_ck_n, ddr4_0_cke, ddr4_0_cs_n,
    output wire        ddr4_0_odt, ddr4_0_reset_n,
    output wire        ddr4_0_par,
    input  wire        ddr4_0_alert_n,
    inout  wire [63:0] ddr4_0_dq,
    inout  wire [7:0]  ddr4_0_dqs, ddr4_0_dqs_n,
    inout  wire [7:0]  ddr4_0_dbi_n
);

wire [31:0] av_address;
wire        av_read, av_write;
wire [31:0] av_writedata, av_readdata;
wire        av_waitrequest, av_readdatavalid;
wire [3:0]  av_byteenable;

wire ninit_done;
wire cal_ok0, cal_fail0;
wire usr_clk0;
wire [15:0] issp_source;
wire [31:0] issp_probe;
wire [95:0] mem_source;
wire [95:0] mem_probe;
wire [35:0] mb_address;
wire [31:0] mb_writedata, mb_readdata;
wire        mb_read, mb_write, mb_waitrequest, mb_readdatavalid;
wire [3:0]  mb_byteenable;
wire        sda_in, scl_in, sda_oe, scl_oe;

// I2C 开漏三态
assign i2c_sda = sda_oe ? 1'b0 : 1'bz;
assign i2c_scl = scl_oe ? 1'b0 : 1'bz;
assign sda_in  = i2c_sda;
assign scl_in  = i2c_scl;

jtag_sys u_jtag (
    .clk_clk               (clk100M),
    .reset_reset           (ninit_done),
    .ninit_done_ninit_done (ninit_done),
    .issp_sources_source   (issp_source),
    .issp_probes_probe     (issp_probe),
    .mem_sources_source    (mem_source),
    .mem_probes_probe      (mem_probe),
    .mem_address           (mb_address),
    .mem_read              (mb_read),
    .mem_write             (mb_write),
    .mem_writedata         (mb_writedata),
    .mem_readdata          (mb_readdata),
    .mem_waitrequest       (mb_waitrequest),
    .mem_readdatavalid     (mb_readdatavalid),
    .mem_byteenable        (mb_byteenable),
    .mem_burstcount        (1'b1),
    .mem_debugaccess       (1'b0),
    .i2c_serial_sda_in     (sda_in),
    .i2c_serial_scl_in     (scl_in),
    .i2c_serial_sda_oe     (sda_oe),
    .i2c_serial_scl_oe     (scl_oe),
    .ddr0_ref_clk_clk      (ddr4_0_ref_clk),
    .ddr0_oct_oct_rzqin    (ddr4_0_rzqin),
    .ddr0_mem_ck           (ddr4_0_ck),
    .ddr0_mem_ck_n         (ddr4_0_ck_n),
    .ddr0_mem_a            (ddr4_0_a),
    .ddr0_mem_act_n        (ddr4_0_act_n),
    .ddr0_mem_ba           (ddr4_0_ba),
    .ddr0_mem_bg           (ddr4_0_bg),
    .ddr0_mem_cke          (ddr4_0_cke),
    .ddr0_mem_cs_n         (ddr4_0_cs_n),
    .ddr0_mem_odt          (ddr4_0_odt),
    .ddr0_mem_reset_n      (ddr4_0_reset_n),
    .ddr0_mem_par          (ddr4_0_par),
    .ddr0_mem_alert_n      (ddr4_0_alert_n),
    .ddr0_mem_dqs          (ddr4_0_dqs),
    .ddr0_mem_dqs_n        (ddr4_0_dqs_n),
    .ddr0_mem_dq           (ddr4_0_dq),
    .ddr0_mem_dbi_n        (ddr4_0_dbi_n),
    .ddr0_status_local_cal_success (cal_ok0),
    .ddr0_status_local_cal_fail    (cal_fail0),
    .ddr0_usrclk_clk       (usr_clk0),
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

// 时钟活动计数: ref_clk 输入 与 EMIF PLL 用户时钟 (通道0)
reg utog = 1'b0;
always @(posedge usr_clk0) utog <= ~utog;
reg [2:0] usy = 3'd0;
always @(posedge clk100M) usy <= {usy[1:0], utog};
reg [3:0] ucnt = 4'd0;
always @(posedge clk100M) if (usy[2] ^ usy[1]) ucnt <= ucnt + 1'b1;

reg rtog = 1'b0;
always @(posedge ddr4_0_ref_clk) rtog <= ~rtog;
reg [2:0] rsy = 3'd0;
always @(posedge clk100M) rsy <= {rsy[1:0], rtog};
reg [3:0] rcnt = 4'd0;
always @(posedge clk100M) if (rsy[2] ^ rsy[1]) rcnt <= rcnt + 1'b1;

// ISSP -> Avalon 命令桥 (通往 cal_debug @0x0 与 I2C @0x80000000)
issp_mem_bridge u_membr (
    .clk              (clk100M),
    .src              (mem_source),
    .prb              (mem_probe),
    .heartbeat        (issp_probe[19:16]),
    .cal_ok           ({3'b000, cal_ok0}),
    .cal_fail         ({3'b000, cal_fail0}),
    .pwr              (3'b000),
    .usr_alive        ({12'd0, ucnt}),
    .ref_alive        ({12'd0, rcnt}),
    .am_address       (mb_address),
    .am_read          (mb_read),
    .am_write         (mb_write),
    .am_writedata     (mb_writedata),
    .am_byteenable    (mb_byteenable),
    .am_readdata      (mb_readdata),
    .am_readdatavalid (mb_readdatavalid),
    .am_waitrequest   (mb_waitrequest)
);

endmodule
