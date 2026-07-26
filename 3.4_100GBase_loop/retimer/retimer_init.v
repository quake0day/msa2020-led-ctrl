// ============================================================================
// retimer_init.v  --  实验4 阶段2: QSFP0 Retimer/I2C 初始化
// ----------------------------------------------------------------------------
// DS250DF810 (retimer) + FPC202 (QSFP 端口控制器) 的 I2C 上电初始化。
// 与收发器物理布局解耦: 纯 I2C 逻辑, 独立可编译。
//   - I2C 主机由 DS250DF810 / FPC202 各自例化, 经 Arbiter 仲裁共享一条 I2C 总线
//   - i2c_scl / i2c_sda 开漏 (线与): 任一主机拉低则为低, 否则 Hi-Z 由板上上拉拉高
//   - ISSP(instance RTMR) 供 PC 读初始化状态 / 触发软复位
// 引脚 (Plugcat 验证): I2C SCL=AC28 SDA=AB28 (3.0-V LVTTL, Bank6A),
//   clock_100=AD6 (1.8V), LED[8:0] Bank (1.8V)
// ============================================================================
module retimer_init (
    input        clock_100,
    output [8:0] led,
    inout        i2c_scl,
    inout        i2c_sda
);

    localparam CLOCK_FREQUENCY = 100_000_000;

    // ---- 复位: 上电 ninit_done + ISSP 软复位 + 计数展宽 ----
    wire ninit_done;
    rstrel u_rstrel (.ninit_done(ninit_done));

    wire [7:0] issp_source;
    wire       soft_reset = issp_source[0];

    reg [3:0] rst_cnt = 4'hF;
    always @(posedge clock_100) begin
        if (ninit_done | soft_reset)
            rst_cnt <= 4'hF;
        else if (rst_cnt != 0)
            rst_cnt <= rst_cnt - 4'd1;
    end
    wire system_reset = (rst_cnt != 0);

    // ---- I2C 开漏总线 (线与) ----
    wire       i2c_scl_input;
    wire [1:0] i2c_scl_output;
    wire       i2c_sda_input;
    wire [1:0] i2c_sda_output;

    assign i2c_scl       = (&i2c_scl_output) ? 1'bz : 1'b0;
    assign i2c_scl_input = i2c_scl;
    assign i2c_sda       = (&i2c_sda_output) ? 1'bz : 1'b0;
    assign i2c_sda_input = i2c_sda;

    // ---- I2C 仲裁: 2 个主机 (DS250DF810, FPC202) ----
    wire [1:0] i2c_request;
    wire [1:0] i2c_grant;
    Arbiter #(.REQUEST_COUNT(2)) u_arbiter (
        .clock   (clock_100),
        .reset   (system_reset),
        .request (i2c_request),
        .grant   (i2c_grant)
    );

    // ---- DS250DF810 retimer 初始化 (I2C addr 0x22/0x23) ----
    wire ds_ready;
    DS250DF810 #(.CLOCK_FREQUENCY(CLOCK_FREQUENCY)) u_ds250 (
        .clock       (clock_100),
        .reset       (system_reset),
        .scl_input   (i2c_scl_input),
        .scl_output  (i2c_scl_output[0]),
        .sda_input   (i2c_sda_input),
        .sda_output  (i2c_sda_output[0]),
        .i2c_request (i2c_request[0]),
        .i2c_grant   (i2c_grant[0]),
        .ready       (ds_ready)
    );

    // ---- FPC202 QSFP 端口控制器 (I2C addr 0x0F) ----
    wire       fpc_ready;
    wire [3:0] fpc_in_a, fpc_in_b, fpc_in_c;
    wire [3:0] fpc_out_a, fpc_out_b;
    FPC202 #(.CLOCK_FREQUENCY(CLOCK_FREQUENCY)) u_fpc202 (
        .clock       (clock_100),
        .reset       (system_reset),
        .scl_input   (i2c_scl_input),
        .scl_output  (i2c_scl_output[1]),
        .sda_input   (i2c_sda_input),
        .sda_output  (i2c_sda_output[1]),
        .i2c_request (i2c_request[1]),
        .i2c_grant   (i2c_grant[1]),
        .ready       (fpc_ready),
        .in_a        (fpc_in_a),
        .in_b        (fpc_in_b),
        .in_c        (fpc_in_c),
        .out_a       (fpc_out_a),
        .out_b       (fpc_out_b)
    );

    // QSFP0/1 modprsl / intl 输入, resetl / lpmode 输出 (经 FPC202 I2C 扩展)
    wire [1:0] qsfp_modprsl = { fpc_in_b[2], fpc_in_b[0] };
    wire [1:0] qsfp_intl    = { fpc_in_a[2], fpc_in_a[0] };
    wire       init_ready   = ds_ready & fpc_ready;
    wire [1:0] qsfp_resetl  = {2{~system_reset & init_ready}}; // 初始化完成后放开 QSFP 复位
    assign fpc_out_a = { 1'b0, qsfp_resetl[1], 1'b0, qsfp_resetl[0] };
    assign fpc_out_b = 4'b0;                                    // lpmode = 0 (全速)

    // ---- ISSP: PC 读状态 / 触发软复位 ----
    //  probe[0]      ds_ready
    //  probe[1]      fpc_ready
    //  probe[2]      init_ready
    //  probe[3]      system_reset
    //  probe[7:4]    fpc_in_a  (QSFP intl 等)
    //  probe[11:8]   fpc_in_b  (QSFP modprsl 等)
    //  probe[15:12]  fpc_in_c
    //  probe[17:16]  qsfp_modprsl
    //  probe[19:18]  qsfp_intl
    //  probe[31:24]  签名 0xR2 (0x52)
    wire [31:0] issp_probe = {
        8'h52,                 // [31:24] 签名
        4'h0,                  // [23:20]
        qsfp_intl,             // [19:18]
        qsfp_modprsl,          // [17:16]
        fpc_in_c,              // [15:12]
        fpc_in_b,              // [11:8]
        fpc_in_a,              // [7:4]
        system_reset,          // [3]
        init_ready,            // [2]
        fpc_ready,             // [1]
        ds_ready               // [0]
    };
    issp_ret u_issp (.source(issp_source), .probe(issp_probe));

    // ---- LED 本地可视 ----
    assign led = {
        3'b0,
        ~system_reset & qsfp_intl[0],
        ~system_reset & qsfp_modprsl[0],
        ~system_reset & init_ready,   // 初始化完成
        ~system_reset & fpc_ready,    // FPC202 完成
        ~system_reset & ds_ready,     // DS250 完成
        ~system_reset                 // 系统运行
    };

endmodule
