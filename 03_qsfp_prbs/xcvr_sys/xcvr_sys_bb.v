module xcvr_sys (
		input  wire        refclk_clk,                                      //                     refclk.clk
		output wire        pll_locked_pll_locked,                           //                 pll_locked.pll_locked
		input  wire        refclk1_clk,                                     //                    refclk1.clk
		output wire        pll_locked1_pll_locked,                          //                pll_locked1.pll_locked
		input  wire        x_tx_analogreset_ch0_tx_analogreset,             //       x_tx_analogreset_ch0.tx_analogreset
		input  wire        x_tx_analogreset_ch1_tx_analogreset,             //       x_tx_analogreset_ch1.tx_analogreset
		input  wire        x_tx_analogreset_ch2_tx_analogreset,             //       x_tx_analogreset_ch2.tx_analogreset
		input  wire        x_tx_analogreset_ch3_tx_analogreset,             //       x_tx_analogreset_ch3.tx_analogreset
		input  wire        x_rx_analogreset_ch0_rx_analogreset,             //       x_rx_analogreset_ch0.rx_analogreset
		input  wire        x_rx_analogreset_ch1_rx_analogreset,             //       x_rx_analogreset_ch1.rx_analogreset
		input  wire        x_rx_analogreset_ch2_rx_analogreset,             //       x_rx_analogreset_ch2.rx_analogreset
		input  wire        x_rx_analogreset_ch3_rx_analogreset,             //       x_rx_analogreset_ch3.rx_analogreset
		input  wire        x_tx_digitalreset_ch0_tx_digitalreset,           //      x_tx_digitalreset_ch0.tx_digitalreset
		input  wire        x_tx_digitalreset_ch1_tx_digitalreset,           //      x_tx_digitalreset_ch1.tx_digitalreset
		input  wire        x_tx_digitalreset_ch2_tx_digitalreset,           //      x_tx_digitalreset_ch2.tx_digitalreset
		input  wire        x_tx_digitalreset_ch3_tx_digitalreset,           //      x_tx_digitalreset_ch3.tx_digitalreset
		input  wire        x_rx_digitalreset_ch0_rx_digitalreset,           //      x_rx_digitalreset_ch0.rx_digitalreset
		input  wire        x_rx_digitalreset_ch1_rx_digitalreset,           //      x_rx_digitalreset_ch1.rx_digitalreset
		input  wire        x_rx_digitalreset_ch2_rx_digitalreset,           //      x_rx_digitalreset_ch2.rx_digitalreset
		input  wire        x_rx_digitalreset_ch3_rx_digitalreset,           //      x_rx_digitalreset_ch3.rx_digitalreset
		output wire        x_tx_analogreset_stat_ch0_tx_analogreset_stat,   //  x_tx_analogreset_stat_ch0.tx_analogreset_stat
		output wire        x_tx_analogreset_stat_ch1_tx_analogreset_stat,   //  x_tx_analogreset_stat_ch1.tx_analogreset_stat
		output wire        x_tx_analogreset_stat_ch2_tx_analogreset_stat,   //  x_tx_analogreset_stat_ch2.tx_analogreset_stat
		output wire        x_tx_analogreset_stat_ch3_tx_analogreset_stat,   //  x_tx_analogreset_stat_ch3.tx_analogreset_stat
		output wire        x_rx_analogreset_stat_ch0_rx_analogreset_stat,   //  x_rx_analogreset_stat_ch0.rx_analogreset_stat
		output wire        x_rx_analogreset_stat_ch1_rx_analogreset_stat,   //  x_rx_analogreset_stat_ch1.rx_analogreset_stat
		output wire        x_rx_analogreset_stat_ch2_rx_analogreset_stat,   //  x_rx_analogreset_stat_ch2.rx_analogreset_stat
		output wire        x_rx_analogreset_stat_ch3_rx_analogreset_stat,   //  x_rx_analogreset_stat_ch3.rx_analogreset_stat
		output wire        x_tx_digitalreset_stat_ch0_tx_digitalreset_stat, // x_tx_digitalreset_stat_ch0.tx_digitalreset_stat
		output wire        x_tx_digitalreset_stat_ch1_tx_digitalreset_stat, // x_tx_digitalreset_stat_ch1.tx_digitalreset_stat
		output wire        x_tx_digitalreset_stat_ch2_tx_digitalreset_stat, // x_tx_digitalreset_stat_ch2.tx_digitalreset_stat
		output wire        x_tx_digitalreset_stat_ch3_tx_digitalreset_stat, // x_tx_digitalreset_stat_ch3.tx_digitalreset_stat
		output wire        x_rx_digitalreset_stat_ch0_rx_digitalreset_stat, // x_rx_digitalreset_stat_ch0.rx_digitalreset_stat
		output wire        x_rx_digitalreset_stat_ch1_rx_digitalreset_stat, // x_rx_digitalreset_stat_ch1.rx_digitalreset_stat
		output wire        x_rx_digitalreset_stat_ch2_rx_digitalreset_stat, // x_rx_digitalreset_stat_ch2.rx_digitalreset_stat
		output wire        x_rx_digitalreset_stat_ch3_rx_digitalreset_stat, // x_rx_digitalreset_stat_ch3.rx_digitalreset_stat
		output wire        x_tx_cal_busy_ch0_tx_cal_busy,                   //          x_tx_cal_busy_ch0.tx_cal_busy
		output wire        x_tx_cal_busy_ch1_tx_cal_busy,                   //          x_tx_cal_busy_ch1.tx_cal_busy
		output wire        x_tx_cal_busy_ch2_tx_cal_busy,                   //          x_tx_cal_busy_ch2.tx_cal_busy
		output wire        x_tx_cal_busy_ch3_tx_cal_busy,                   //          x_tx_cal_busy_ch3.tx_cal_busy
		output wire        x_rx_cal_busy_ch0_rx_cal_busy,                   //          x_rx_cal_busy_ch0.rx_cal_busy
		output wire        x_rx_cal_busy_ch1_rx_cal_busy,                   //          x_rx_cal_busy_ch1.rx_cal_busy
		output wire        x_rx_cal_busy_ch2_rx_cal_busy,                   //          x_rx_cal_busy_ch2.rx_cal_busy
		output wire        x_rx_cal_busy_ch3_rx_cal_busy,                   //          x_rx_cal_busy_ch3.rx_cal_busy
		input  wire        x_rx_cdr_refclk0_clk,                            //           x_rx_cdr_refclk0.clk
		output wire        x_tx_serial_data_ch0_tx_serial_data,             //       x_tx_serial_data_ch0.tx_serial_data
		output wire        x_tx_serial_data_ch1_tx_serial_data,             //       x_tx_serial_data_ch1.tx_serial_data
		output wire        x_tx_serial_data_ch2_tx_serial_data,             //       x_tx_serial_data_ch2.tx_serial_data
		output wire        x_tx_serial_data_ch3_tx_serial_data,             //       x_tx_serial_data_ch3.tx_serial_data
		input  wire        x_rx_serial_data_ch0_rx_serial_data,             //       x_rx_serial_data_ch0.rx_serial_data
		input  wire        x_rx_serial_data_ch1_rx_serial_data,             //       x_rx_serial_data_ch1.rx_serial_data
		input  wire        x_rx_serial_data_ch2_rx_serial_data,             //       x_rx_serial_data_ch2.rx_serial_data
		input  wire        x_rx_serial_data_ch3_rx_serial_data,             //       x_rx_serial_data_ch3.rx_serial_data
		input  wire        x_rx_seriallpbken_ch0_rx_seriallpbken,           //      x_rx_seriallpbken_ch0.rx_seriallpbken
		input  wire        x_rx_seriallpbken_ch1_rx_seriallpbken,           //      x_rx_seriallpbken_ch1.rx_seriallpbken
		input  wire        x_rx_seriallpbken_ch2_rx_seriallpbken,           //      x_rx_seriallpbken_ch2.rx_seriallpbken
		input  wire        x_rx_seriallpbken_ch3_rx_seriallpbken,           //      x_rx_seriallpbken_ch3.rx_seriallpbken
		output wire        x_rx_is_lockedtoref_ch0_rx_is_lockedtoref,       //    x_rx_is_lockedtoref_ch0.rx_is_lockedtoref
		output wire        x_rx_is_lockedtoref_ch1_rx_is_lockedtoref,       //    x_rx_is_lockedtoref_ch1.rx_is_lockedtoref
		output wire        x_rx_is_lockedtoref_ch2_rx_is_lockedtoref,       //    x_rx_is_lockedtoref_ch2.rx_is_lockedtoref
		output wire        x_rx_is_lockedtoref_ch3_rx_is_lockedtoref,       //    x_rx_is_lockedtoref_ch3.rx_is_lockedtoref
		output wire        x_rx_is_lockedtodata_ch0_rx_is_lockedtodata,     //   x_rx_is_lockedtodata_ch0.rx_is_lockedtodata
		output wire        x_rx_is_lockedtodata_ch1_rx_is_lockedtodata,     //   x_rx_is_lockedtodata_ch1.rx_is_lockedtodata
		output wire        x_rx_is_lockedtodata_ch2_rx_is_lockedtodata,     //   x_rx_is_lockedtodata_ch2.rx_is_lockedtodata
		output wire        x_rx_is_lockedtodata_ch3_rx_is_lockedtodata,     //   x_rx_is_lockedtodata_ch3.rx_is_lockedtodata
		input  wire        x_tx_coreclkin_ch0_clk,                          //         x_tx_coreclkin_ch0.clk
		input  wire        x_tx_coreclkin_ch1_clk,                          //         x_tx_coreclkin_ch1.clk
		input  wire        x_tx_coreclkin_ch2_clk,                          //         x_tx_coreclkin_ch2.clk
		input  wire        x_tx_coreclkin_ch3_clk,                          //         x_tx_coreclkin_ch3.clk
		input  wire        x_rx_coreclkin_ch0_clk,                          //         x_rx_coreclkin_ch0.clk
		input  wire        x_rx_coreclkin_ch1_clk,                          //         x_rx_coreclkin_ch1.clk
		input  wire        x_rx_coreclkin_ch2_clk,                          //         x_rx_coreclkin_ch2.clk
		input  wire        x_rx_coreclkin_ch3_clk,                          //         x_rx_coreclkin_ch3.clk
		output wire        x_tx_clkout_ch0_clk,                             //            x_tx_clkout_ch0.clk
		output wire        x_tx_clkout_ch1_clk,                             //            x_tx_clkout_ch1.clk
		output wire        x_tx_clkout_ch2_clk,                             //            x_tx_clkout_ch2.clk
		output wire        x_tx_clkout_ch3_clk,                             //            x_tx_clkout_ch3.clk
		output wire        x_rx_clkout_ch0_clk,                             //            x_rx_clkout_ch0.clk
		output wire        x_rx_clkout_ch1_clk,                             //            x_rx_clkout_ch1.clk
		output wire        x_rx_clkout_ch2_clk,                             //            x_rx_clkout_ch2.clk
		output wire        x_rx_clkout_ch3_clk,                             //            x_rx_clkout_ch3.clk
		input  wire [79:0] x_tx_parallel_data_ch0_tx_parallel_data,         //     x_tx_parallel_data_ch0.tx_parallel_data
		input  wire [79:0] x_tx_parallel_data_ch1_tx_parallel_data,         //     x_tx_parallel_data_ch1.tx_parallel_data
		input  wire [79:0] x_tx_parallel_data_ch2_tx_parallel_data,         //     x_tx_parallel_data_ch2.tx_parallel_data
		input  wire [79:0] x_tx_parallel_data_ch3_tx_parallel_data,         //     x_tx_parallel_data_ch3.tx_parallel_data
		output wire [79:0] x_rx_parallel_data_ch0_rx_parallel_data,         //     x_rx_parallel_data_ch0.rx_parallel_data
		output wire [79:0] x_rx_parallel_data_ch1_rx_parallel_data,         //     x_rx_parallel_data_ch1.rx_parallel_data
		output wire [79:0] x_rx_parallel_data_ch2_rx_parallel_data,         //     x_rx_parallel_data_ch2.rx_parallel_data
		output wire [79:0] x_rx_parallel_data_ch3_rx_parallel_data,         //     x_rx_parallel_data_ch3.rx_parallel_data
		input  wire        f_tx_analogreset_ch0_tx_analogreset,             //       f_tx_analogreset_ch0.tx_analogreset
		input  wire        f_tx_analogreset_ch1_tx_analogreset,             //       f_tx_analogreset_ch1.tx_analogreset
		input  wire        f_tx_digitalreset_ch0_tx_digitalreset,           //      f_tx_digitalreset_ch0.tx_digitalreset
		input  wire        f_tx_digitalreset_ch1_tx_digitalreset,           //      f_tx_digitalreset_ch1.tx_digitalreset
		output wire        f_tx_analogreset_stat_ch0_tx_analogreset_stat,   //  f_tx_analogreset_stat_ch0.tx_analogreset_stat
		output wire        f_tx_analogreset_stat_ch1_tx_analogreset_stat,   //  f_tx_analogreset_stat_ch1.tx_analogreset_stat
		output wire        f_tx_digitalreset_stat_ch0_tx_digitalreset_stat, // f_tx_digitalreset_stat_ch0.tx_digitalreset_stat
		output wire        f_tx_digitalreset_stat_ch1_tx_digitalreset_stat, // f_tx_digitalreset_stat_ch1.tx_digitalreset_stat
		output wire        f_tx_cal_busy_ch0_tx_cal_busy,                   //          f_tx_cal_busy_ch0.tx_cal_busy
		output wire        f_tx_cal_busy_ch1_tx_cal_busy,                   //          f_tx_cal_busy_ch1.tx_cal_busy
		output wire        f_tx_serial_data_ch0_tx_serial_data,             //       f_tx_serial_data_ch0.tx_serial_data
		output wire        f_tx_serial_data_ch1_tx_serial_data,             //       f_tx_serial_data_ch1.tx_serial_data
		input  wire        f_tx_coreclkin_ch0_clk,                          //         f_tx_coreclkin_ch0.clk
		input  wire        f_tx_coreclkin_ch1_clk,                          //         f_tx_coreclkin_ch1.clk
		output wire        f_tx_clkout_ch0_clk,                             //            f_tx_clkout_ch0.clk
		output wire        f_tx_clkout_ch1_clk,                             //            f_tx_clkout_ch1.clk
		input  wire [79:0] f_tx_parallel_data_ch0_tx_parallel_data,         //     f_tx_parallel_data_ch0.tx_parallel_data
		input  wire [79:0] f_tx_parallel_data_ch1_tx_parallel_data          //     f_tx_parallel_data_ch1.tx_parallel_data
	);
endmodule

