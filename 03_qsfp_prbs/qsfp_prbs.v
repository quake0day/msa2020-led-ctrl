// 实验3: QSFP0 4x25.78125G GXT PRBS 环回
// 主PHY 4通道 duplex(QSFP) + 填充PHY 2通道 tx-only(填6pack,HIGH_PERF,无CDR)
// GXT 时钟: 双ATX(GXT direct).tx_serial_clk_gxt -> 分通道; 内部串行环回 PRBS31
module qsfp_prbs (
    input  wire clk100M, output wire [8:0] LED,
    input  wire qsfp0_refclk, output wire [3:0] qsfp0_tx, input wire [3:0] qsfp0_rx
);
wire ninit_done; rstrel u_rstrel (.ninit_done(ninit_done));
wire [15:0] xcv_src; wire [95:0] xcv_prb;
issp_xcvr u_issp (.source(xcv_src), .probe(xcv_prb));
wire lpbk_en=xcv_src[0]; wire cnt_clear=xcv_src[1]; wire usr_reset=xcv_src[2];
wire [1:0] ch_sel=xcv_src[4:3]; wire sys_reset=ninit_done|usr_reset;
wire pll_locked0,pll_locked1; wire pll_locked=pll_locked0&pll_locked1;
wire frst=sys_reset;  // 填充通道复位 (随主复位)
wire [1:0] fclk;
wire [3:0] tx_arst,rx_arst,tx_drst,rx_drst,tx_arst_stat,rx_arst_stat,tx_drst_stat,rx_drst_stat;
wire [3:0] tx_calb,rx_calb,tx_ready,rx_ready,rx_lref,rx_ldata,tx_clk,rx_clk;
wire [3:0] lpbk4={4{lpbk_en}};
wire [79:0] tx_pdata[0:3]; wire [79:0] rx_pdata[0:3];
rstctrl0 u_rst (.clock(clk100M),.reset(sys_reset),.pll_locked(pll_locked),.pll_select(1'b0),
    .tx_analogreset(tx_arst),.tx_digitalreset(tx_drst),.tx_ready(tx_ready),.tx_cal_busy(tx_calb),
    .tx_analogreset_stat(tx_arst_stat),.tx_digitalreset_stat(tx_drst_stat),
    .rx_analogreset(rx_arst),.rx_digitalreset(rx_drst),.rx_ready(rx_ready),
    .rx_is_lockedtodata(rx_ldata),.rx_cal_busy(rx_calb),
    .rx_analogreset_stat(rx_arst_stat),.rx_digitalreset_stat(rx_drst_stat));

xcvr_sys u_xcvr (
    .refclk_clk (qsfp0_refclk), .refclk1_clk (qsfp0_refclk),
    .pll_locked_pll_locked (pll_locked0), .pll_locked1_pll_locked (pll_locked1),
    .x_rx_cdr_refclk0_clk (qsfp0_refclk),
    .x_tx_analogreset_ch0_tx_analogreset (tx_arst[0]),
    .x_tx_analogreset_ch1_tx_analogreset (tx_arst[1]),
    .x_tx_analogreset_ch2_tx_analogreset (tx_arst[2]),
    .x_tx_analogreset_ch3_tx_analogreset (tx_arst[3]),
    .x_rx_analogreset_ch0_rx_analogreset (rx_arst[0]),
    .x_rx_analogreset_ch1_rx_analogreset (rx_arst[1]),
    .x_rx_analogreset_ch2_rx_analogreset (rx_arst[2]),
    .x_rx_analogreset_ch3_rx_analogreset (rx_arst[3]),
    .x_tx_digitalreset_ch0_tx_digitalreset (tx_drst[0]),
    .x_tx_digitalreset_ch1_tx_digitalreset (tx_drst[1]),
    .x_tx_digitalreset_ch2_tx_digitalreset (tx_drst[2]),
    .x_tx_digitalreset_ch3_tx_digitalreset (tx_drst[3]),
    .x_rx_digitalreset_ch0_rx_digitalreset (rx_drst[0]),
    .x_rx_digitalreset_ch1_rx_digitalreset (rx_drst[1]),
    .x_rx_digitalreset_ch2_rx_digitalreset (rx_drst[2]),
    .x_rx_digitalreset_ch3_rx_digitalreset (rx_drst[3]),
    .x_rx_seriallpbken_ch0_rx_seriallpbken (lpbk4[0]),
    .x_rx_seriallpbken_ch1_rx_seriallpbken (lpbk4[1]),
    .x_rx_seriallpbken_ch2_rx_seriallpbken (lpbk4[2]),
    .x_rx_seriallpbken_ch3_rx_seriallpbken (lpbk4[3]),
    .x_tx_coreclkin_ch0_clk (tx_clk[0]),
    .x_tx_coreclkin_ch1_clk (tx_clk[1]),
    .x_tx_coreclkin_ch2_clk (tx_clk[2]),
    .x_tx_coreclkin_ch3_clk (tx_clk[3]),
    .x_rx_coreclkin_ch0_clk (rx_clk[0]),
    .x_rx_coreclkin_ch1_clk (rx_clk[1]),
    .x_rx_coreclkin_ch2_clk (rx_clk[2]),
    .x_rx_coreclkin_ch3_clk (rx_clk[3]),
    .x_tx_analogreset_stat_ch0_tx_analogreset_stat (tx_arst_stat[0]),
    .x_tx_analogreset_stat_ch1_tx_analogreset_stat (tx_arst_stat[1]),
    .x_tx_analogreset_stat_ch2_tx_analogreset_stat (tx_arst_stat[2]),
    .x_tx_analogreset_stat_ch3_tx_analogreset_stat (tx_arst_stat[3]),
    .x_rx_analogreset_stat_ch0_rx_analogreset_stat (rx_arst_stat[0]),
    .x_rx_analogreset_stat_ch1_rx_analogreset_stat (rx_arst_stat[1]),
    .x_rx_analogreset_stat_ch2_rx_analogreset_stat (rx_arst_stat[2]),
    .x_rx_analogreset_stat_ch3_rx_analogreset_stat (rx_arst_stat[3]),
    .x_tx_digitalreset_stat_ch0_tx_digitalreset_stat (tx_drst_stat[0]),
    .x_tx_digitalreset_stat_ch1_tx_digitalreset_stat (tx_drst_stat[1]),
    .x_tx_digitalreset_stat_ch2_tx_digitalreset_stat (tx_drst_stat[2]),
    .x_tx_digitalreset_stat_ch3_tx_digitalreset_stat (tx_drst_stat[3]),
    .x_rx_digitalreset_stat_ch0_rx_digitalreset_stat (rx_drst_stat[0]),
    .x_rx_digitalreset_stat_ch1_rx_digitalreset_stat (rx_drst_stat[1]),
    .x_rx_digitalreset_stat_ch2_rx_digitalreset_stat (rx_drst_stat[2]),
    .x_rx_digitalreset_stat_ch3_rx_digitalreset_stat (rx_drst_stat[3]),
    .x_tx_cal_busy_ch0_tx_cal_busy (tx_calb[0]),
    .x_tx_cal_busy_ch1_tx_cal_busy (tx_calb[1]),
    .x_tx_cal_busy_ch2_tx_cal_busy (tx_calb[2]),
    .x_tx_cal_busy_ch3_tx_cal_busy (tx_calb[3]),
    .x_rx_cal_busy_ch0_rx_cal_busy (rx_calb[0]),
    .x_rx_cal_busy_ch1_rx_cal_busy (rx_calb[1]),
    .x_rx_cal_busy_ch2_rx_cal_busy (rx_calb[2]),
    .x_rx_cal_busy_ch3_rx_cal_busy (rx_calb[3]),
    .x_rx_is_lockedtoref_ch0_rx_is_lockedtoref (rx_lref[0]),
    .x_rx_is_lockedtoref_ch1_rx_is_lockedtoref (rx_lref[1]),
    .x_rx_is_lockedtoref_ch2_rx_is_lockedtoref (rx_lref[2]),
    .x_rx_is_lockedtoref_ch3_rx_is_lockedtoref (rx_lref[3]),
    .x_rx_is_lockedtodata_ch0_rx_is_lockedtodata (rx_ldata[0]),
    .x_rx_is_lockedtodata_ch1_rx_is_lockedtodata (rx_ldata[1]),
    .x_rx_is_lockedtodata_ch2_rx_is_lockedtodata (rx_ldata[2]),
    .x_rx_is_lockedtodata_ch3_rx_is_lockedtodata (rx_ldata[3]),
    .x_tx_clkout_ch0_clk (tx_clk[0]),
    .x_tx_clkout_ch1_clk (tx_clk[1]),
    .x_tx_clkout_ch2_clk (tx_clk[2]),
    .x_tx_clkout_ch3_clk (tx_clk[3]),
    .x_rx_clkout_ch0_clk (rx_clk[0]),
    .x_rx_clkout_ch1_clk (rx_clk[1]),
    .x_rx_clkout_ch2_clk (rx_clk[2]),
    .x_rx_clkout_ch3_clk (rx_clk[3]),
    .x_tx_serial_data_ch0_tx_serial_data (qsfp0_tx[0]),
    .x_tx_serial_data_ch1_tx_serial_data (qsfp0_tx[1]),
    .x_tx_serial_data_ch2_tx_serial_data (qsfp0_tx[2]),
    .x_tx_serial_data_ch3_tx_serial_data (qsfp0_tx[3]),
    .x_rx_serial_data_ch0_rx_serial_data (qsfp0_rx[0]),
    .x_rx_serial_data_ch1_rx_serial_data (qsfp0_rx[1]),
    .x_rx_serial_data_ch2_rx_serial_data (qsfp0_rx[2]),
    .x_rx_serial_data_ch3_rx_serial_data (qsfp0_rx[3]),
    .x_tx_parallel_data_ch0_tx_parallel_data (tx_pdata[0]),
    .x_tx_parallel_data_ch1_tx_parallel_data (tx_pdata[1]),
    .x_tx_parallel_data_ch2_tx_parallel_data (tx_pdata[2]),
    .x_tx_parallel_data_ch3_tx_parallel_data (tx_pdata[3]),
    .x_rx_parallel_data_ch0_rx_parallel_data (rx_pdata[0]),
    .x_rx_parallel_data_ch1_rx_parallel_data (rx_pdata[1]),
    .x_rx_parallel_data_ch2_rx_parallel_data (rx_pdata[2]),
    .x_rx_parallel_data_ch3_rx_parallel_data (rx_pdata[3]),
    .f_tx_analogreset_ch0_tx_analogreset (frst),
    .f_tx_digitalreset_ch0_tx_digitalreset (frst),
    .f_tx_analogreset_stat_ch0_tx_analogreset_stat (),
    .f_tx_digitalreset_stat_ch0_tx_digitalreset_stat (),
    .f_tx_cal_busy_ch0_tx_cal_busy (),
    .f_tx_coreclkin_ch0_clk (fclk[0]),
    .f_tx_clkout_ch0_clk (fclk[0]),
    .f_tx_parallel_data_ch0_tx_parallel_data (80'd0),
    .f_tx_serial_data_ch0_tx_serial_data (),
    .f_tx_analogreset_ch1_tx_analogreset (frst),
    .f_tx_digitalreset_ch1_tx_digitalreset (frst),
    .f_tx_analogreset_stat_ch1_tx_analogreset_stat (),
    .f_tx_digitalreset_stat_ch1_tx_digitalreset_stat (),
    .f_tx_cal_busy_ch1_tx_cal_busy (),
    .f_tx_coreclkin_ch1_clk (fclk[1]),
    .f_tx_clkout_ch1_clk (fclk[1]),
    .f_tx_parallel_data_ch1_tx_parallel_data (80'd0),
    .f_tx_serial_data_ch1_tx_serial_data ()
);

wire [31:0] err_count[0:3]; wire [3:0] err_seen;
genvar g;
generate for (g=0;g<4;g=g+1) begin: ch
    reg [1:0] txs=2'b11; always @(posedge tx_clk[g]) txs<={txs[0],~tx_ready[g]};
    prbs31_gen #(.W(80)) gen (.clk(tx_clk[g]),.rst(txs[1]),.dout(tx_pdata[g]));
    reg [1:0] rxs=2'b11,clr=2'b00;
    always @(posedge rx_clk[g]) begin rxs<={rxs[0],~rx_ready[g]}; clr<={clr[0],cnt_clear}; end
    prbs31_chk #(.W(80)) chk (.clk(rx_clk[g]),.rst(rxs[1]),.din(rx_pdata[g]),
        .clear(clr[1]),.err_count(err_count[g]),.err_seen(err_seen[g]));
end endgenerate
reg [26:0] hb=27'd0; always @(posedge clk100M) hb<=hb+1'b1;
assign xcv_prb={8'h3C,19'd0,hb[26],pll_locked,err_seen,err_count[ch_sel],
    rx_ldata,rx_lref,rx_ready,tx_ready};
assign LED={hb[26],~err_seen,rx_ready};
endmodule
