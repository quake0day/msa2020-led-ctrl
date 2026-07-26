// 实验3: 100GbE MAC 收发器点亮 (MSA-2020, 4x25.78125G QSFP0)
// 用 alt_e100s10 (内部收发器布局 Intel 已解 GXT 死结) + 2 外部 ATX PLL
// ISSP(MAC) 读 tx_lanes_stable/rx_pcs_ready/rx_block_lock/rx_am_lock
// 环回下 block_lock/am_lock 拉高 = 4x25.78G 链路通 (外部环回或 reconfig 内环回)
module qsfp_100g (
    input  wire clk100M, output wire [8:0] LED,
    input  wire qsfp0_refclk, output wire [3:0] qsfp0_tx, input wire [3:0] qsfp0_rx
);
wire ninit_done; rstrel u_rstrel (.ninit_done(ninit_done));
wire [7:0] mac_src; wire [31:0] mac_prb;
issp_mac u_issp (.source(mac_src), .probe(mac_prb));
wire usr_reset = mac_src[0];
wire sys_reset = ninit_done | usr_reset;

// 级联 ATX PLL 对 (Intel alt_e100s10 模板正解): master 经 gxt_output_to_blw_atx
// 级联到 slave 的 gxt_input_from_abv_atx, 二者 tx_serial_clk_gxt 各喂 MAC 一路。
// {serial_clk_1(master), serial_clk_2(slave)} = tx_serial_clk[1:0];
// tx_pll_locked 两位都取 master 的 locked (模板 assign pll_locked={l1,l1})。
wire [1:0] tx_serial_clk;
wire       atx_cascade;
wire       atx_m_locked, atx_s_locked;
// master 在下三联组(靠 refclk AD34), 向上级联给 slave (上三联组)
macatx_m u_atx_m (.pll_refclk0(qsfp0_refclk), .tx_serial_clk(),
    .tx_serial_clk_gxt(tx_serial_clk[0]),
    .gxt_output_to_abv_atx(atx_cascade),
    .pll_locked(atx_m_locked), .pll_cal_busy());
macatx_s u_atx_s (.pll_refclk0(qsfp0_refclk), .tx_serial_clk(),
    .tx_serial_clk_gxt(tx_serial_clk[1]),
    .gxt_input_from_blw_atx(atx_cascade),
    .pll_locked(atx_s_locked), .pll_cal_busy());
wire [1:0] tx_pll_locked = {atx_m_locked, atx_m_locked};

wire rst_n = ~sys_reset & (&tx_pll_locked);
reg [3:0] rs = 4'd0; always @(posedge clk100M) rs <= {rs[2:0], rst_n};
wire mac_rst_n = rs[3];

wire tx_lanes_stable, rx_pcs_ready, rx_block_lock, rx_am_lock;
wire clk_txmac, clk_rxmac;

e100 u_mac (
    .clk_ref(qsfp0_refclk),
    .tx_serial_clk(tx_serial_clk), .tx_pll_locked(tx_pll_locked),
    .tx_serial(qsfp0_tx), .rx_serial(qsfp0_rx),
    .reconfig_clk(clk100M), .reconfig_reset(sys_reset),
    .reconfig_write(1'b0), .reconfig_read(1'b0), .reconfig_address(13'd0),
    .reconfig_writedata(32'd0), .reconfig_readdata(), .reconfig_waitrequest(),
    .clk_status(clk100M), .status_write(1'b0), .status_read(1'b0),
    .status_addr(16'd0), .status_writedata(32'd0), .status_readdata(),
    .status_readdata_valid(), .status_waitrequest(),
    .csr_rst_n(mac_rst_n), .tx_rst_n(mac_rst_n), .rx_rst_n(mac_rst_n),
    .clk_txmac(clk_txmac),
    .l8_tx_startofpacket(1'b0), .l8_tx_endofpacket(1'b0), .l8_tx_valid(1'b0),
    .l8_tx_ready(), .l8_tx_error(1'b0), .l8_tx_empty(6'd0), .l8_tx_data(512'd0),
    .clk_rxmac(clk_rxmac),
    .l8_rx_error(), .l8_rx_valid(), .l8_rx_startofpacket(), .l8_rx_endofpacket(),
    .l8_rx_empty(), .l8_rx_data(),
    .l8_txstatus_valid(), .l8_txstatus_data(), .l8_txstatus_error(),
    .l8_rxstatus_valid(), .l8_rxstatus_data(),
    .tx_lanes_stable(tx_lanes_stable), .rx_pcs_ready(rx_pcs_ready),
    .rx_block_lock(rx_block_lock), .rx_am_lock(rx_am_lock)
);

reg [26:0] hb = 27'd0; always @(posedge clk100M) hb <= hb + 1'b1;
assign mac_prb = {8'h1C, 12'd0, hb[26], tx_pll_locked,
    tx_lanes_stable, rx_pcs_ready, rx_block_lock, rx_am_lock};
assign LED = {hb[26], 4'd0, rx_am_lock, rx_block_lock, rx_pcs_ready, tx_lanes_stable};
endmodule
