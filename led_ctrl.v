// led_ctrl -- 顶层 (DDR4 侦察版): JTAG 桥 + LED 核心 + ISSP 内存桥
//             + 4 通道 EMIF DDR4 (全部例化, 定位哪个物理槽有可用内存)
// 探针可见: 4 通道校准状态 + 板卡电源状态 (12V / SWITCH_GD / DDR_LDO_GD)
// 数据通路: mm_bridge -> emif2 (丝印 DIMM2)
module led_ctrl (
    input  wire       clk100M,
    output wire [8:0] LED,
    // (PINDEF PIN 表 LED 列的 12V/SWITCH_GD/DDR_LDO_GD 实测均非 FPGA 用户 IO,
    //  电源状态无法从 FPGA 读取, 只能看板上实体指示灯)
    // DDR4 x4 通道 (引脚由 gen_ddr_pins.py 生成)
    input  wire        ddr4_0_ref_clk, ddr4_0_rzqin,
    output wire [16:0] ddr4_0_a,
    output wire        ddr4_0_act_n,
    output wire [1:0]  ddr4_0_ba, ddr4_0_bg,
    output wire        ddr4_0_ck, ddr4_0_ck_n, ddr4_0_cke, ddr4_0_cs_n,
    output wire        ddr4_0_odt, ddr4_0_reset_n,
    inout  wire [63:0] ddr4_0_dq,
    inout  wire [7:0]  ddr4_0_dqs, ddr4_0_dqs_n,
    inout  wire [7:0]  ddr4_0_dbi_n,

    input  wire        ddr4_1_ref_clk, ddr4_1_rzqin,
    output wire [16:0] ddr4_1_a,
    output wire        ddr4_1_act_n,
    output wire [1:0]  ddr4_1_ba, ddr4_1_bg,
    output wire        ddr4_1_ck, ddr4_1_ck_n, ddr4_1_cke, ddr4_1_cs_n,
    output wire        ddr4_1_odt, ddr4_1_reset_n,
    inout  wire [63:0] ddr4_1_dq,
    inout  wire [7:0]  ddr4_1_dqs, ddr4_1_dqs_n,
    inout  wire [7:0]  ddr4_1_dbi_n,

    input  wire        ddr4_2_ref_clk, ddr4_2_rzqin,
    output wire [16:0] ddr4_2_a,
    output wire        ddr4_2_act_n,
    output wire [1:0]  ddr4_2_ba, ddr4_2_bg,
    output wire        ddr4_2_ck, ddr4_2_ck_n, ddr4_2_cke, ddr4_2_cs_n,
    output wire        ddr4_2_odt, ddr4_2_reset_n,
    inout  wire [63:0] ddr4_2_dq,
    inout  wire [7:0]  ddr4_2_dqs, ddr4_2_dqs_n,
    inout  wire [7:0]  ddr4_2_dbi_n,

    input  wire        ddr4_3_ref_clk, ddr4_3_rzqin,
    output wire [16:0] ddr4_3_a,
    output wire        ddr4_3_act_n,
    output wire [1:0]  ddr4_3_ba, ddr4_3_bg,
    output wire        ddr4_3_ck, ddr4_3_ck_n, ddr4_3_cke, ddr4_3_cs_n,
    output wire        ddr4_3_odt, ddr4_3_reset_n,
    inout  wire [63:0] ddr4_3_dq,
    inout  wire [7:0]  ddr4_3_dqs, ddr4_3_dqs_n,
    inout  wire [7:0]  ddr4_3_dbi_n
);

wire [31:0] av_address;
wire        av_read, av_write;
wire [31:0] av_writedata, av_readdata;
wire        av_waitrequest, av_readdatavalid;
wire [3:0]  av_byteenable;

wire ninit_done;
wire [3:0] cal_ok, cal_fail;
wire [3:0] usr_clk;                 // 各 EMIF usr_clk 输出
wire [15:0] issp_source;
wire [31:0] issp_probe;
wire [95:0] mem_source;
wire [95:0] mem_probe;
wire [31:0] mb_address, mb_writedata, mb_readdata;
wire        mb_read, mb_write, mb_waitrequest, mb_readdatavalid;
wire [3:0]  mb_byteenable;

jtag_sys u_jtag (
    .clk_clk               (clk100M),
    .reset_reset           (ninit_done),
    .ninit_done_ninit_done (ninit_done),
    .issp_sources_source   (issp_source),
    .issp_probes_probe     (issp_probe),
    .mem_sources_source    (mem_source),
    .mem_probes_probe      (mem_probe),
    // ISSP 内存桥数据通路 (经 mm_bridge 通往 emif2)
    .mem_address           ({1'b0, mb_address}),
    .mem_read              (mb_read),
    .mem_write             (mb_write),
    .mem_writedata         (mb_writedata),
    .mem_readdata          (mb_readdata),
    .mem_waitrequest       (mb_waitrequest),
    .mem_readdatavalid     (mb_readdatavalid),
    .mem_byteenable        (mb_byteenable),
    .mem_burstcount        (1'b1),
    .mem_debugaccess       (1'b0),
    // DDR4 通道 0 (丝印 DIMM0)
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
    .ddr0_mem_dqs          (ddr4_0_dqs),
    .ddr0_mem_dqs_n        (ddr4_0_dqs_n),
    .ddr0_mem_dq           (ddr4_0_dq),
    .ddr0_mem_dbi_n       (ddr4_0_dbi_n),
    .ddr0_status_local_cal_success (cal_ok[0]),
    .ddr0_status_local_cal_fail    (cal_fail[0]),
    .ddr0_ctrl_read        (1'b0),
    .ddr0_ctrl_write       (1'b0),
    .ddr0_ctrl_address     (27'd0),
    .ddr0_ctrl_writedata   (512'd0),
    .ddr0_ctrl_burstcount  (7'd1),
    .ddr0_ctrl_waitrequest_n (),
    .ddr0_ctrl_readdata      (),
    .ddr0_ctrl_readdatavalid (),
    // DDR4 通道 1 (丝印 DIMM1)
    .ddr1_ref_clk_clk      (ddr4_1_ref_clk),
    .ddr1_oct_oct_rzqin    (ddr4_1_rzqin),
    .ddr1_mem_ck           (ddr4_1_ck),
    .ddr1_mem_ck_n         (ddr4_1_ck_n),
    .ddr1_mem_a            (ddr4_1_a),
    .ddr1_mem_act_n        (ddr4_1_act_n),
    .ddr1_mem_ba           (ddr4_1_ba),
    .ddr1_mem_bg           (ddr4_1_bg),
    .ddr1_mem_cke          (ddr4_1_cke),
    .ddr1_mem_cs_n         (ddr4_1_cs_n),
    .ddr1_mem_odt          (ddr4_1_odt),
    .ddr1_mem_reset_n      (ddr4_1_reset_n),
    .ddr1_mem_dqs          (ddr4_1_dqs),
    .ddr1_mem_dqs_n        (ddr4_1_dqs_n),
    .ddr1_mem_dq           (ddr4_1_dq),
    .ddr1_mem_dbi_n       (ddr4_1_dbi_n),
    .ddr1_status_local_cal_success (cal_ok[1]),
    .ddr1_status_local_cal_fail    (cal_fail[1]),
    .ddr1_ctrl_read        (1'b0),
    .ddr1_ctrl_write       (1'b0),
    .ddr1_ctrl_address     (27'd0),
    .ddr1_ctrl_writedata   (512'd0),
    .ddr1_ctrl_burstcount  (7'd1),
    .ddr1_ctrl_waitrequest_n (),
    .ddr1_ctrl_readdata      (),
    .ddr1_ctrl_readdatavalid (),
    // DDR4 通道 2 (丝印 DIMM2, 数据通路挂 mm_bridge)
    .ddr2_ref_clk_clk      (ddr4_2_ref_clk),
    .ddr2_oct_oct_rzqin    (ddr4_2_rzqin),
    .ddr2_mem_ck           (ddr4_2_ck),
    .ddr2_mem_ck_n         (ddr4_2_ck_n),
    .ddr2_mem_a            (ddr4_2_a),
    .ddr2_mem_act_n        (ddr4_2_act_n),
    .ddr2_mem_ba           (ddr4_2_ba),
    .ddr2_mem_bg           (ddr4_2_bg),
    .ddr2_mem_cke          (ddr4_2_cke),
    .ddr2_mem_cs_n         (ddr4_2_cs_n),
    .ddr2_mem_odt          (ddr4_2_odt),
    .ddr2_mem_reset_n      (ddr4_2_reset_n),
    .ddr2_mem_dqs          (ddr4_2_dqs),
    .ddr2_mem_dqs_n        (ddr4_2_dqs_n),
    .ddr2_mem_dq           (ddr4_2_dq),
    .ddr2_mem_dbi_n       (ddr4_2_dbi_n),
    .ddr2_status_local_cal_success (cal_ok[2]),
    .ddr2_status_local_cal_fail    (cal_fail[2]),
    // DDR4 通道 3 (丝印 DIMM3)
    .ddr3_ref_clk_clk      (ddr4_3_ref_clk),
    .ddr3_oct_oct_rzqin    (ddr4_3_rzqin),
    .ddr3_mem_ck           (ddr4_3_ck),
    .ddr3_mem_ck_n         (ddr4_3_ck_n),
    .ddr3_mem_a            (ddr4_3_a),
    .ddr3_mem_act_n        (ddr4_3_act_n),
    .ddr3_mem_ba           (ddr4_3_ba),
    .ddr3_mem_bg           (ddr4_3_bg),
    .ddr3_mem_cke          (ddr4_3_cke),
    .ddr3_mem_cs_n         (ddr4_3_cs_n),
    .ddr3_mem_odt          (ddr4_3_odt),
    .ddr3_mem_reset_n      (ddr4_3_reset_n),
    .ddr3_mem_dqs          (ddr4_3_dqs),
    .ddr3_mem_dqs_n        (ddr4_3_dqs_n),
    .ddr3_mem_dq           (ddr4_3_dq),
    .ddr3_mem_dbi_n       (ddr4_3_dbi_n),
    .ddr3_status_local_cal_success (cal_ok[3]),
    .ddr3_status_local_cal_fail    (cal_fail[3]),
    .ddr0_usrclk_clk       (usr_clk[0]),
    .ddr1_usrclk_clk       (usr_clk[1]),
    .ddr2_usrclk_clk       (usr_clk[2]),
    .ddr3_usrclk_clk       (usr_clk[3]),
    .ddr3_ctrl_read        (1'b0),
    .ddr3_ctrl_write       (1'b0),
    .ddr3_ctrl_address     (27'd0),
    .ddr3_ctrl_writedata   (512'd0),
    .ddr3_ctrl_burstcount  (7'd1),
    .ddr3_ctrl_waitrequest_n (),
    .ddr3_ctrl_readdata      (),
    .ddr3_ctrl_readdatavalid (),
    // JTAG-Avalon 桥 (备用)
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

// usr_clk 频率计: 每通道用户时钟翻转 -> 同步到 clk100M -> 活动计数
// (计数在增长 = 该 EMIF 的 PLL 已锁定 = 150MHz 参考时钟真实存在)
wire [3:0] usr_alive_bit;
genvar gi;
generate
    for (gi = 0; gi < 4; gi = gi + 1) begin : usrmon
        reg tog = 1'b0;
        always @(posedge usr_clk[gi]) tog <= ~tog;
        reg [2:0] sy = 3'd0;
        always @(posedge clk100M) sy <= {sy[1:0], tog};
        assign usr_alive_bit[gi] = sy[2] ^ sy[1];   // 每次翻转脉冲一拍
    end
endgenerate
reg [15:0] usr_alive = 16'd0;
always @(posedge clk100M) begin
    if (usr_alive_bit[0]) usr_alive[3:0]   <= usr_alive[3:0]   + 1'b1;
    if (usr_alive_bit[1]) usr_alive[7:4]   <= usr_alive[7:4]   + 1'b1;
    if (usr_alive_bit[2]) usr_alive[11:8]  <= usr_alive[11:8]  + 1'b1;
    if (usr_alive_bit[3]) usr_alive[15:12] <= usr_alive[15:12] + 1'b1;
end

// ref_clk 输入频率计: 直接监测 4 个参考时钟输入脚是否有信号
// (增长 = 该 ref_clk 脚有时钟 -> 时钟源 5P49V5901 在输出)
wire [3:0] refc = {ddr4_3_ref_clk, ddr4_2_ref_clk,
                   ddr4_1_ref_clk, ddr4_0_ref_clk};
wire [3:0] ref_alive_bit;
generate
    for (gi = 0; gi < 4; gi = gi + 1) begin : refmon
        reg rtog = 1'b0;
        always @(posedge refc[gi]) rtog <= ~rtog;
        reg [2:0] rsy = 3'd0;
        always @(posedge clk100M) rsy <= {rsy[1:0], rtog};
        assign ref_alive_bit[gi] = rsy[2] ^ rsy[1];
    end
endgenerate
reg [15:0] ref_alive = 16'd0;
always @(posedge clk100M) begin
    if (ref_alive_bit[0]) ref_alive[3:0]   <= ref_alive[3:0]   + 1'b1;
    if (ref_alive_bit[1]) ref_alive[7:4]   <= ref_alive[7:4]   + 1'b1;
    if (ref_alive_bit[2]) ref_alive[11:8]  <= ref_alive[11:8]  + 1'b1;
    if (ref_alive_bit[3]) ref_alive[15:12] <= ref_alive[15:12] + 1'b1;
end

// ISSP -> Avalon 内存命令桥 (数据通路: emif2 / 丝印 DIMM2)
issp_mem_bridge u_membr (
    .clk              (clk100M),
    .src              (mem_source),
    .prb              (mem_probe),
    .heartbeat        (issp_probe[19:16]),
    .cal_ok           (cal_ok),
    .cal_fail         (cal_fail),
    .pwr              (3'b000),
    .usr_alive        (usr_alive),
    .ref_alive        (ref_alive),
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
