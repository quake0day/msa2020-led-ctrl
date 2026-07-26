// ============================================================================
// qsfp_xcvr.v  --  实验6 阶段1: QSFP0 4×25.78G GXT 收发器点亮 (PRBS31)
// ----------------------------------------------------------------------------
// 基于 Corundum 520N_MX 已验证拓扑 (eth_xcvr_phy_quad_wrapper):
//   master ATX(atx_lcl) + GXT 缓冲(atx_blw) + 4×单通道 Native PHY(GXT,
//   CDR refclk 走 IQ 网络), 单 refclk AD34 服务 4 通道。PCS 内建 PRBS31。
// anlg_link=sr (本板 1SG280LN2 只在 short-reach 支持 25.78G)。
// ISSP(XCVR, 签名 0x1C): 读各通道 block_lock/high_ber/err, 控制 PRBS/复位。
// ============================================================================
module qsfp_xcvr (
    input  wire        clock_100,        // AD6, 1.8V 控制/重配时钟
    input  wire        qsfp0_refclk,     // AD34, 644.53125MHz GXT refclk
    output wire [3:0]  qsfp0_tx,
    input  wire [3:0]  qsfp0_rx,
    output wire [8:0]  led
);
    // ---- 复位 ----
    wire ninit_done;  rstrel u_rstrel (.ninit_done(ninit_done));
    wire [7:0] src;   wire [31:0] prb;
    issp_xcv u_issp (.source(src), .probe(prb));
    wire soft_rst = src[0];
    wire prbs_en  = src[1] | 1'b1;        // 默认开 PRBS31 (可被 ISSP 覆盖保持)
    wire [1:0] ch_sel = src[3:2];

    reg [3:0] rstsync = 4'hF;
    always @(posedge clock_100) begin
        if (ninit_done | soft_rst) rstsync <= 4'hF;
        else                       rstsync <= {rstsync[2:0], 1'b0};
    end
    wire ctrl_rst = rstsync[3];

    // ---- 各通道状态线 ----
    wire [3:0] blk_lock, high_ber, rx_status;
    wire [6:0] err_cnt [3:0];
    wire [3:0] tx_bad, rx_bad, rx_seq_err;

    // ---- 诊断: PLL 锁定 / 校准 + 各通道收发时钟活动 ----
    wire dbg_pll_locked, dbg_pll_cal_busy;
    wire [3:0] phy_tx_clk, phy_rx_clk;

    // ---- QSFP0 四通道收发器 (Corundum quad wrapper) ----
    eth_xcvr_phy_quad_wrapper #(
        .GXT           (1),
        .DATA_WIDTH    (64),
        .PRBS31_ENABLE (1)
    ) u_qsfp0 (
        .xcvr_ctrl_clk (clock_100),
        .xcvr_ctrl_rst (ctrl_rst),
        .xcvr_ref_clk  (qsfp0_refclk),
        .xcvr_tx_serial_data (qsfp0_tx),
        .xcvr_rx_serial_data (qsfp0_rx),
        .dbg_gxt_pll_locked(dbg_pll_locked), .dbg_gxt_pll_cal_busy(dbg_pll_cal_busy),

        .phy_1_tx_clk(phy_tx_clk[0]), .phy_1_tx_rst(), .phy_1_xgmii_txd(64'd0), .phy_1_xgmii_txc(8'd0),
        .phy_1_rx_clk(phy_rx_clk[0]), .phy_1_rx_rst(), .phy_1_xgmii_rxd(), .phy_1_xgmii_rxc(),
        .phy_1_tx_bad_block(tx_bad[0]), .phy_1_rx_error_count(err_cnt[0]),
        .phy_1_rx_bad_block(rx_bad[0]), .phy_1_rx_sequence_error(rx_seq_err[0]),
        .phy_1_rx_block_lock(blk_lock[0]), .phy_1_rx_high_ber(high_ber[0]),
        .phy_1_rx_status(rx_status[0]),
        .phy_1_cfg_tx_prbs31_enable(prbs_en), .phy_1_cfg_rx_prbs31_enable(prbs_en),

        .phy_2_tx_clk(phy_tx_clk[1]), .phy_2_tx_rst(), .phy_2_xgmii_txd(64'd0), .phy_2_xgmii_txc(8'd0),
        .phy_2_rx_clk(phy_rx_clk[1]), .phy_2_rx_rst(), .phy_2_xgmii_rxd(), .phy_2_xgmii_rxc(),
        .phy_2_tx_bad_block(tx_bad[1]), .phy_2_rx_error_count(err_cnt[1]),
        .phy_2_rx_bad_block(rx_bad[1]), .phy_2_rx_sequence_error(rx_seq_err[1]),
        .phy_2_rx_block_lock(blk_lock[1]), .phy_2_rx_high_ber(high_ber[1]),
        .phy_2_rx_status(rx_status[1]),
        .phy_2_cfg_tx_prbs31_enable(prbs_en), .phy_2_cfg_rx_prbs31_enable(prbs_en),

        .phy_3_tx_clk(phy_tx_clk[2]), .phy_3_tx_rst(), .phy_3_xgmii_txd(64'd0), .phy_3_xgmii_txc(8'd0),
        .phy_3_rx_clk(phy_rx_clk[2]), .phy_3_rx_rst(), .phy_3_xgmii_rxd(), .phy_3_xgmii_rxc(),
        .phy_3_tx_bad_block(tx_bad[2]), .phy_3_rx_error_count(err_cnt[2]),
        .phy_3_rx_bad_block(rx_bad[2]), .phy_3_rx_sequence_error(rx_seq_err[2]),
        .phy_3_rx_block_lock(blk_lock[2]), .phy_3_rx_high_ber(high_ber[2]),
        .phy_3_rx_status(rx_status[2]),
        .phy_3_cfg_tx_prbs31_enable(prbs_en), .phy_3_cfg_rx_prbs31_enable(prbs_en),

        .phy_4_tx_clk(phy_tx_clk[3]), .phy_4_tx_rst(), .phy_4_xgmii_txd(64'd0), .phy_4_xgmii_txc(8'd0),
        .phy_4_rx_clk(phy_rx_clk[3]), .phy_4_rx_rst(), .phy_4_xgmii_rxd(), .phy_4_xgmii_rxc(),
        .phy_4_tx_bad_block(tx_bad[3]), .phy_4_rx_error_count(err_cnt[3]),
        .phy_4_rx_bad_block(rx_bad[3]), .phy_4_rx_sequence_error(rx_seq_err[3]),
        .phy_4_rx_block_lock(blk_lock[3]), .phy_4_rx_high_ber(high_ber[3]),
        .phy_4_rx_status(rx_status[3]),
        .phy_4_cfg_tx_prbs31_enable(prbs_en), .phy_4_cfg_rx_prbs31_enable(prbs_en)
    );

    // ---- PLL 锁定/校准 同步到 clock_100 ----
    reg [1:0] pll_lk_s, pll_cb_s;
    always @(posedge clock_100) begin
        pll_lk_s <= {pll_lk_s[0], dbg_pll_locked};
        pll_cb_s <= {pll_cb_s[0], dbg_pll_cal_busy};
    end
    wire pll_locked   = pll_lk_s[1];
    wire pll_cal_busy = pll_cb_s[1];

    // ---- 各通道收发时钟活动检测 (sticky: 复位后是否翻转过=时钟在跑) ----
    wire [3:0] tx_act, rx_act;
    genvar c;
    generate for (c = 0; c < 4; c = c + 1) begin: clkdet
        (* keep *) reg tgl_tx = 1'b0, tgl_rx = 1'b0;
        always @(posedge phy_tx_clk[c]) tgl_tx <= ~tgl_tx;
        always @(posedge phy_rx_clk[c]) tgl_rx <= ~tgl_rx;
        reg [2:0] s_tx, s_rx;
        reg sticky_tx, sticky_rx;
        always @(posedge clock_100) begin
            s_tx <= {s_tx[1:0], tgl_tx};
            s_rx <= {s_rx[1:0], tgl_rx};
            if (ctrl_rst) begin sticky_tx <= 1'b0; sticky_rx <= 1'b0; end
            else begin
                if (s_tx[2] ^ s_tx[1]) sticky_tx <= 1'b1;
                if (s_rx[2] ^ s_rx[1]) sticky_rx <= 1'b1;
            end
        end
        assign tx_act[c] = sticky_tx;
        assign rx_act[c] = sticky_rx;
    end endgenerate

    // ---- 误码累加 (每通道, 32bit 饱和), 经 ISSP 选通道读回 ----
    reg [31:0] errsum [3:0];
    genvar g;
    generate for (g = 0; g < 4; g = g + 1) begin: acc
        always @(posedge clock_100) begin
            if (ctrl_rst)                         errsum[g] <= 32'd0;
            else if (errsum[g] < 32'hFFFF0000)    errsum[g] <= errsum[g] + err_cnt[g];
        end
    end endgenerate

    // ---- ISSP probe ----
    // PRBS31 模式下 block_lock/high_ber 是 64b/66b 帧指示, 无意义;
    // 真正的 PRBS 锁定指标 = errsum 是否停止增长(误码率)。
    //  [1:0]=00  [2]pll_locked  [3]pll_cal_busy  [7:4]rx_act
    //  [23:8]=errsum[ch_sel][15:0]  [31:24]=0x1C 签名
    assign prb = {
        8'h1C,
        errsum[ch_sel][15:0],
        rx_act,
        pll_cal_busy,
        pll_locked,
        2'b0
    };

    assign led = {
        pll_locked,
        ~ctrl_rst,
        |high_ber,
        &rx_act,            // 4 通道恢复时钟都在跑
        blk_lock
    };
endmodule
