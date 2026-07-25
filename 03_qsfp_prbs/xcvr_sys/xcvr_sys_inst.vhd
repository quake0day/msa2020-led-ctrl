	component xcvr_sys is
		port (
			refclk_clk                                      : in  std_logic                     := 'X';             -- clk
			pll_locked_pll_locked                           : out std_logic;                                        -- pll_locked
			refclk1_clk                                     : in  std_logic                     := 'X';             -- clk
			pll_locked1_pll_locked                          : out std_logic;                                        -- pll_locked
			x_tx_analogreset_ch0_tx_analogreset             : in  std_logic                     := 'X';             -- tx_analogreset
			x_tx_analogreset_ch1_tx_analogreset             : in  std_logic                     := 'X';             -- tx_analogreset
			x_tx_analogreset_ch2_tx_analogreset             : in  std_logic                     := 'X';             -- tx_analogreset
			x_tx_analogreset_ch3_tx_analogreset             : in  std_logic                     := 'X';             -- tx_analogreset
			x_rx_analogreset_ch0_rx_analogreset             : in  std_logic                     := 'X';             -- rx_analogreset
			x_rx_analogreset_ch1_rx_analogreset             : in  std_logic                     := 'X';             -- rx_analogreset
			x_rx_analogreset_ch2_rx_analogreset             : in  std_logic                     := 'X';             -- rx_analogreset
			x_rx_analogreset_ch3_rx_analogreset             : in  std_logic                     := 'X';             -- rx_analogreset
			x_tx_digitalreset_ch0_tx_digitalreset           : in  std_logic                     := 'X';             -- tx_digitalreset
			x_tx_digitalreset_ch1_tx_digitalreset           : in  std_logic                     := 'X';             -- tx_digitalreset
			x_tx_digitalreset_ch2_tx_digitalreset           : in  std_logic                     := 'X';             -- tx_digitalreset
			x_tx_digitalreset_ch3_tx_digitalreset           : in  std_logic                     := 'X';             -- tx_digitalreset
			x_rx_digitalreset_ch0_rx_digitalreset           : in  std_logic                     := 'X';             -- rx_digitalreset
			x_rx_digitalreset_ch1_rx_digitalreset           : in  std_logic                     := 'X';             -- rx_digitalreset
			x_rx_digitalreset_ch2_rx_digitalreset           : in  std_logic                     := 'X';             -- rx_digitalreset
			x_rx_digitalreset_ch3_rx_digitalreset           : in  std_logic                     := 'X';             -- rx_digitalreset
			x_tx_analogreset_stat_ch0_tx_analogreset_stat   : out std_logic;                                        -- tx_analogreset_stat
			x_tx_analogreset_stat_ch1_tx_analogreset_stat   : out std_logic;                                        -- tx_analogreset_stat
			x_tx_analogreset_stat_ch2_tx_analogreset_stat   : out std_logic;                                        -- tx_analogreset_stat
			x_tx_analogreset_stat_ch3_tx_analogreset_stat   : out std_logic;                                        -- tx_analogreset_stat
			x_rx_analogreset_stat_ch0_rx_analogreset_stat   : out std_logic;                                        -- rx_analogreset_stat
			x_rx_analogreset_stat_ch1_rx_analogreset_stat   : out std_logic;                                        -- rx_analogreset_stat
			x_rx_analogreset_stat_ch2_rx_analogreset_stat   : out std_logic;                                        -- rx_analogreset_stat
			x_rx_analogreset_stat_ch3_rx_analogreset_stat   : out std_logic;                                        -- rx_analogreset_stat
			x_tx_digitalreset_stat_ch0_tx_digitalreset_stat : out std_logic;                                        -- tx_digitalreset_stat
			x_tx_digitalreset_stat_ch1_tx_digitalreset_stat : out std_logic;                                        -- tx_digitalreset_stat
			x_tx_digitalreset_stat_ch2_tx_digitalreset_stat : out std_logic;                                        -- tx_digitalreset_stat
			x_tx_digitalreset_stat_ch3_tx_digitalreset_stat : out std_logic;                                        -- tx_digitalreset_stat
			x_rx_digitalreset_stat_ch0_rx_digitalreset_stat : out std_logic;                                        -- rx_digitalreset_stat
			x_rx_digitalreset_stat_ch1_rx_digitalreset_stat : out std_logic;                                        -- rx_digitalreset_stat
			x_rx_digitalreset_stat_ch2_rx_digitalreset_stat : out std_logic;                                        -- rx_digitalreset_stat
			x_rx_digitalreset_stat_ch3_rx_digitalreset_stat : out std_logic;                                        -- rx_digitalreset_stat
			x_tx_cal_busy_ch0_tx_cal_busy                   : out std_logic;                                        -- tx_cal_busy
			x_tx_cal_busy_ch1_tx_cal_busy                   : out std_logic;                                        -- tx_cal_busy
			x_tx_cal_busy_ch2_tx_cal_busy                   : out std_logic;                                        -- tx_cal_busy
			x_tx_cal_busy_ch3_tx_cal_busy                   : out std_logic;                                        -- tx_cal_busy
			x_rx_cal_busy_ch0_rx_cal_busy                   : out std_logic;                                        -- rx_cal_busy
			x_rx_cal_busy_ch1_rx_cal_busy                   : out std_logic;                                        -- rx_cal_busy
			x_rx_cal_busy_ch2_rx_cal_busy                   : out std_logic;                                        -- rx_cal_busy
			x_rx_cal_busy_ch3_rx_cal_busy                   : out std_logic;                                        -- rx_cal_busy
			x_rx_cdr_refclk0_clk                            : in  std_logic                     := 'X';             -- clk
			x_tx_serial_data_ch0_tx_serial_data             : out std_logic;                                        -- tx_serial_data
			x_tx_serial_data_ch1_tx_serial_data             : out std_logic;                                        -- tx_serial_data
			x_tx_serial_data_ch2_tx_serial_data             : out std_logic;                                        -- tx_serial_data
			x_tx_serial_data_ch3_tx_serial_data             : out std_logic;                                        -- tx_serial_data
			x_rx_serial_data_ch0_rx_serial_data             : in  std_logic                     := 'X';             -- rx_serial_data
			x_rx_serial_data_ch1_rx_serial_data             : in  std_logic                     := 'X';             -- rx_serial_data
			x_rx_serial_data_ch2_rx_serial_data             : in  std_logic                     := 'X';             -- rx_serial_data
			x_rx_serial_data_ch3_rx_serial_data             : in  std_logic                     := 'X';             -- rx_serial_data
			x_rx_seriallpbken_ch0_rx_seriallpbken           : in  std_logic                     := 'X';             -- rx_seriallpbken
			x_rx_seriallpbken_ch1_rx_seriallpbken           : in  std_logic                     := 'X';             -- rx_seriallpbken
			x_rx_seriallpbken_ch2_rx_seriallpbken           : in  std_logic                     := 'X';             -- rx_seriallpbken
			x_rx_seriallpbken_ch3_rx_seriallpbken           : in  std_logic                     := 'X';             -- rx_seriallpbken
			x_rx_is_lockedtoref_ch0_rx_is_lockedtoref       : out std_logic;                                        -- rx_is_lockedtoref
			x_rx_is_lockedtoref_ch1_rx_is_lockedtoref       : out std_logic;                                        -- rx_is_lockedtoref
			x_rx_is_lockedtoref_ch2_rx_is_lockedtoref       : out std_logic;                                        -- rx_is_lockedtoref
			x_rx_is_lockedtoref_ch3_rx_is_lockedtoref       : out std_logic;                                        -- rx_is_lockedtoref
			x_rx_is_lockedtodata_ch0_rx_is_lockedtodata     : out std_logic;                                        -- rx_is_lockedtodata
			x_rx_is_lockedtodata_ch1_rx_is_lockedtodata     : out std_logic;                                        -- rx_is_lockedtodata
			x_rx_is_lockedtodata_ch2_rx_is_lockedtodata     : out std_logic;                                        -- rx_is_lockedtodata
			x_rx_is_lockedtodata_ch3_rx_is_lockedtodata     : out std_logic;                                        -- rx_is_lockedtodata
			x_tx_coreclkin_ch0_clk                          : in  std_logic                     := 'X';             -- clk
			x_tx_coreclkin_ch1_clk                          : in  std_logic                     := 'X';             -- clk
			x_tx_coreclkin_ch2_clk                          : in  std_logic                     := 'X';             -- clk
			x_tx_coreclkin_ch3_clk                          : in  std_logic                     := 'X';             -- clk
			x_rx_coreclkin_ch0_clk                          : in  std_logic                     := 'X';             -- clk
			x_rx_coreclkin_ch1_clk                          : in  std_logic                     := 'X';             -- clk
			x_rx_coreclkin_ch2_clk                          : in  std_logic                     := 'X';             -- clk
			x_rx_coreclkin_ch3_clk                          : in  std_logic                     := 'X';             -- clk
			x_tx_clkout_ch0_clk                             : out std_logic;                                        -- clk
			x_tx_clkout_ch1_clk                             : out std_logic;                                        -- clk
			x_tx_clkout_ch2_clk                             : out std_logic;                                        -- clk
			x_tx_clkout_ch3_clk                             : out std_logic;                                        -- clk
			x_rx_clkout_ch0_clk                             : out std_logic;                                        -- clk
			x_rx_clkout_ch1_clk                             : out std_logic;                                        -- clk
			x_rx_clkout_ch2_clk                             : out std_logic;                                        -- clk
			x_rx_clkout_ch3_clk                             : out std_logic;                                        -- clk
			x_tx_parallel_data_ch0_tx_parallel_data         : in  std_logic_vector(79 downto 0) := (others => 'X'); -- tx_parallel_data
			x_tx_parallel_data_ch1_tx_parallel_data         : in  std_logic_vector(79 downto 0) := (others => 'X'); -- tx_parallel_data
			x_tx_parallel_data_ch2_tx_parallel_data         : in  std_logic_vector(79 downto 0) := (others => 'X'); -- tx_parallel_data
			x_tx_parallel_data_ch3_tx_parallel_data         : in  std_logic_vector(79 downto 0) := (others => 'X'); -- tx_parallel_data
			x_rx_parallel_data_ch0_rx_parallel_data         : out std_logic_vector(79 downto 0);                    -- rx_parallel_data
			x_rx_parallel_data_ch1_rx_parallel_data         : out std_logic_vector(79 downto 0);                    -- rx_parallel_data
			x_rx_parallel_data_ch2_rx_parallel_data         : out std_logic_vector(79 downto 0);                    -- rx_parallel_data
			x_rx_parallel_data_ch3_rx_parallel_data         : out std_logic_vector(79 downto 0);                    -- rx_parallel_data
			f_tx_analogreset_ch0_tx_analogreset             : in  std_logic                     := 'X';             -- tx_analogreset
			f_tx_analogreset_ch1_tx_analogreset             : in  std_logic                     := 'X';             -- tx_analogreset
			f_tx_digitalreset_ch0_tx_digitalreset           : in  std_logic                     := 'X';             -- tx_digitalreset
			f_tx_digitalreset_ch1_tx_digitalreset           : in  std_logic                     := 'X';             -- tx_digitalreset
			f_tx_analogreset_stat_ch0_tx_analogreset_stat   : out std_logic;                                        -- tx_analogreset_stat
			f_tx_analogreset_stat_ch1_tx_analogreset_stat   : out std_logic;                                        -- tx_analogreset_stat
			f_tx_digitalreset_stat_ch0_tx_digitalreset_stat : out std_logic;                                        -- tx_digitalreset_stat
			f_tx_digitalreset_stat_ch1_tx_digitalreset_stat : out std_logic;                                        -- tx_digitalreset_stat
			f_tx_cal_busy_ch0_tx_cal_busy                   : out std_logic;                                        -- tx_cal_busy
			f_tx_cal_busy_ch1_tx_cal_busy                   : out std_logic;                                        -- tx_cal_busy
			f_tx_serial_data_ch0_tx_serial_data             : out std_logic;                                        -- tx_serial_data
			f_tx_serial_data_ch1_tx_serial_data             : out std_logic;                                        -- tx_serial_data
			f_tx_coreclkin_ch0_clk                          : in  std_logic                     := 'X';             -- clk
			f_tx_coreclkin_ch1_clk                          : in  std_logic                     := 'X';             -- clk
			f_tx_clkout_ch0_clk                             : out std_logic;                                        -- clk
			f_tx_clkout_ch1_clk                             : out std_logic;                                        -- clk
			f_tx_parallel_data_ch0_tx_parallel_data         : in  std_logic_vector(79 downto 0) := (others => 'X'); -- tx_parallel_data
			f_tx_parallel_data_ch1_tx_parallel_data         : in  std_logic_vector(79 downto 0) := (others => 'X')  -- tx_parallel_data
		);
	end component xcvr_sys;

	u0 : component xcvr_sys
		port map (
			refclk_clk                                      => CONNECTED_TO_refclk_clk,                                      --                     refclk.clk
			pll_locked_pll_locked                           => CONNECTED_TO_pll_locked_pll_locked,                           --                 pll_locked.pll_locked
			refclk1_clk                                     => CONNECTED_TO_refclk1_clk,                                     --                    refclk1.clk
			pll_locked1_pll_locked                          => CONNECTED_TO_pll_locked1_pll_locked,                          --                pll_locked1.pll_locked
			x_tx_analogreset_ch0_tx_analogreset             => CONNECTED_TO_x_tx_analogreset_ch0_tx_analogreset,             --       x_tx_analogreset_ch0.tx_analogreset
			x_tx_analogreset_ch1_tx_analogreset             => CONNECTED_TO_x_tx_analogreset_ch1_tx_analogreset,             --       x_tx_analogreset_ch1.tx_analogreset
			x_tx_analogreset_ch2_tx_analogreset             => CONNECTED_TO_x_tx_analogreset_ch2_tx_analogreset,             --       x_tx_analogreset_ch2.tx_analogreset
			x_tx_analogreset_ch3_tx_analogreset             => CONNECTED_TO_x_tx_analogreset_ch3_tx_analogreset,             --       x_tx_analogreset_ch3.tx_analogreset
			x_rx_analogreset_ch0_rx_analogreset             => CONNECTED_TO_x_rx_analogreset_ch0_rx_analogreset,             --       x_rx_analogreset_ch0.rx_analogreset
			x_rx_analogreset_ch1_rx_analogreset             => CONNECTED_TO_x_rx_analogreset_ch1_rx_analogreset,             --       x_rx_analogreset_ch1.rx_analogreset
			x_rx_analogreset_ch2_rx_analogreset             => CONNECTED_TO_x_rx_analogreset_ch2_rx_analogreset,             --       x_rx_analogreset_ch2.rx_analogreset
			x_rx_analogreset_ch3_rx_analogreset             => CONNECTED_TO_x_rx_analogreset_ch3_rx_analogreset,             --       x_rx_analogreset_ch3.rx_analogreset
			x_tx_digitalreset_ch0_tx_digitalreset           => CONNECTED_TO_x_tx_digitalreset_ch0_tx_digitalreset,           --      x_tx_digitalreset_ch0.tx_digitalreset
			x_tx_digitalreset_ch1_tx_digitalreset           => CONNECTED_TO_x_tx_digitalreset_ch1_tx_digitalreset,           --      x_tx_digitalreset_ch1.tx_digitalreset
			x_tx_digitalreset_ch2_tx_digitalreset           => CONNECTED_TO_x_tx_digitalreset_ch2_tx_digitalreset,           --      x_tx_digitalreset_ch2.tx_digitalreset
			x_tx_digitalreset_ch3_tx_digitalreset           => CONNECTED_TO_x_tx_digitalreset_ch3_tx_digitalreset,           --      x_tx_digitalreset_ch3.tx_digitalreset
			x_rx_digitalreset_ch0_rx_digitalreset           => CONNECTED_TO_x_rx_digitalreset_ch0_rx_digitalreset,           --      x_rx_digitalreset_ch0.rx_digitalreset
			x_rx_digitalreset_ch1_rx_digitalreset           => CONNECTED_TO_x_rx_digitalreset_ch1_rx_digitalreset,           --      x_rx_digitalreset_ch1.rx_digitalreset
			x_rx_digitalreset_ch2_rx_digitalreset           => CONNECTED_TO_x_rx_digitalreset_ch2_rx_digitalreset,           --      x_rx_digitalreset_ch2.rx_digitalreset
			x_rx_digitalreset_ch3_rx_digitalreset           => CONNECTED_TO_x_rx_digitalreset_ch3_rx_digitalreset,           --      x_rx_digitalreset_ch3.rx_digitalreset
			x_tx_analogreset_stat_ch0_tx_analogreset_stat   => CONNECTED_TO_x_tx_analogreset_stat_ch0_tx_analogreset_stat,   --  x_tx_analogreset_stat_ch0.tx_analogreset_stat
			x_tx_analogreset_stat_ch1_tx_analogreset_stat   => CONNECTED_TO_x_tx_analogreset_stat_ch1_tx_analogreset_stat,   --  x_tx_analogreset_stat_ch1.tx_analogreset_stat
			x_tx_analogreset_stat_ch2_tx_analogreset_stat   => CONNECTED_TO_x_tx_analogreset_stat_ch2_tx_analogreset_stat,   --  x_tx_analogreset_stat_ch2.tx_analogreset_stat
			x_tx_analogreset_stat_ch3_tx_analogreset_stat   => CONNECTED_TO_x_tx_analogreset_stat_ch3_tx_analogreset_stat,   --  x_tx_analogreset_stat_ch3.tx_analogreset_stat
			x_rx_analogreset_stat_ch0_rx_analogreset_stat   => CONNECTED_TO_x_rx_analogreset_stat_ch0_rx_analogreset_stat,   --  x_rx_analogreset_stat_ch0.rx_analogreset_stat
			x_rx_analogreset_stat_ch1_rx_analogreset_stat   => CONNECTED_TO_x_rx_analogreset_stat_ch1_rx_analogreset_stat,   --  x_rx_analogreset_stat_ch1.rx_analogreset_stat
			x_rx_analogreset_stat_ch2_rx_analogreset_stat   => CONNECTED_TO_x_rx_analogreset_stat_ch2_rx_analogreset_stat,   --  x_rx_analogreset_stat_ch2.rx_analogreset_stat
			x_rx_analogreset_stat_ch3_rx_analogreset_stat   => CONNECTED_TO_x_rx_analogreset_stat_ch3_rx_analogreset_stat,   --  x_rx_analogreset_stat_ch3.rx_analogreset_stat
			x_tx_digitalreset_stat_ch0_tx_digitalreset_stat => CONNECTED_TO_x_tx_digitalreset_stat_ch0_tx_digitalreset_stat, -- x_tx_digitalreset_stat_ch0.tx_digitalreset_stat
			x_tx_digitalreset_stat_ch1_tx_digitalreset_stat => CONNECTED_TO_x_tx_digitalreset_stat_ch1_tx_digitalreset_stat, -- x_tx_digitalreset_stat_ch1.tx_digitalreset_stat
			x_tx_digitalreset_stat_ch2_tx_digitalreset_stat => CONNECTED_TO_x_tx_digitalreset_stat_ch2_tx_digitalreset_stat, -- x_tx_digitalreset_stat_ch2.tx_digitalreset_stat
			x_tx_digitalreset_stat_ch3_tx_digitalreset_stat => CONNECTED_TO_x_tx_digitalreset_stat_ch3_tx_digitalreset_stat, -- x_tx_digitalreset_stat_ch3.tx_digitalreset_stat
			x_rx_digitalreset_stat_ch0_rx_digitalreset_stat => CONNECTED_TO_x_rx_digitalreset_stat_ch0_rx_digitalreset_stat, -- x_rx_digitalreset_stat_ch0.rx_digitalreset_stat
			x_rx_digitalreset_stat_ch1_rx_digitalreset_stat => CONNECTED_TO_x_rx_digitalreset_stat_ch1_rx_digitalreset_stat, -- x_rx_digitalreset_stat_ch1.rx_digitalreset_stat
			x_rx_digitalreset_stat_ch2_rx_digitalreset_stat => CONNECTED_TO_x_rx_digitalreset_stat_ch2_rx_digitalreset_stat, -- x_rx_digitalreset_stat_ch2.rx_digitalreset_stat
			x_rx_digitalreset_stat_ch3_rx_digitalreset_stat => CONNECTED_TO_x_rx_digitalreset_stat_ch3_rx_digitalreset_stat, -- x_rx_digitalreset_stat_ch3.rx_digitalreset_stat
			x_tx_cal_busy_ch0_tx_cal_busy                   => CONNECTED_TO_x_tx_cal_busy_ch0_tx_cal_busy,                   --          x_tx_cal_busy_ch0.tx_cal_busy
			x_tx_cal_busy_ch1_tx_cal_busy                   => CONNECTED_TO_x_tx_cal_busy_ch1_tx_cal_busy,                   --          x_tx_cal_busy_ch1.tx_cal_busy
			x_tx_cal_busy_ch2_tx_cal_busy                   => CONNECTED_TO_x_tx_cal_busy_ch2_tx_cal_busy,                   --          x_tx_cal_busy_ch2.tx_cal_busy
			x_tx_cal_busy_ch3_tx_cal_busy                   => CONNECTED_TO_x_tx_cal_busy_ch3_tx_cal_busy,                   --          x_tx_cal_busy_ch3.tx_cal_busy
			x_rx_cal_busy_ch0_rx_cal_busy                   => CONNECTED_TO_x_rx_cal_busy_ch0_rx_cal_busy,                   --          x_rx_cal_busy_ch0.rx_cal_busy
			x_rx_cal_busy_ch1_rx_cal_busy                   => CONNECTED_TO_x_rx_cal_busy_ch1_rx_cal_busy,                   --          x_rx_cal_busy_ch1.rx_cal_busy
			x_rx_cal_busy_ch2_rx_cal_busy                   => CONNECTED_TO_x_rx_cal_busy_ch2_rx_cal_busy,                   --          x_rx_cal_busy_ch2.rx_cal_busy
			x_rx_cal_busy_ch3_rx_cal_busy                   => CONNECTED_TO_x_rx_cal_busy_ch3_rx_cal_busy,                   --          x_rx_cal_busy_ch3.rx_cal_busy
			x_rx_cdr_refclk0_clk                            => CONNECTED_TO_x_rx_cdr_refclk0_clk,                            --           x_rx_cdr_refclk0.clk
			x_tx_serial_data_ch0_tx_serial_data             => CONNECTED_TO_x_tx_serial_data_ch0_tx_serial_data,             --       x_tx_serial_data_ch0.tx_serial_data
			x_tx_serial_data_ch1_tx_serial_data             => CONNECTED_TO_x_tx_serial_data_ch1_tx_serial_data,             --       x_tx_serial_data_ch1.tx_serial_data
			x_tx_serial_data_ch2_tx_serial_data             => CONNECTED_TO_x_tx_serial_data_ch2_tx_serial_data,             --       x_tx_serial_data_ch2.tx_serial_data
			x_tx_serial_data_ch3_tx_serial_data             => CONNECTED_TO_x_tx_serial_data_ch3_tx_serial_data,             --       x_tx_serial_data_ch3.tx_serial_data
			x_rx_serial_data_ch0_rx_serial_data             => CONNECTED_TO_x_rx_serial_data_ch0_rx_serial_data,             --       x_rx_serial_data_ch0.rx_serial_data
			x_rx_serial_data_ch1_rx_serial_data             => CONNECTED_TO_x_rx_serial_data_ch1_rx_serial_data,             --       x_rx_serial_data_ch1.rx_serial_data
			x_rx_serial_data_ch2_rx_serial_data             => CONNECTED_TO_x_rx_serial_data_ch2_rx_serial_data,             --       x_rx_serial_data_ch2.rx_serial_data
			x_rx_serial_data_ch3_rx_serial_data             => CONNECTED_TO_x_rx_serial_data_ch3_rx_serial_data,             --       x_rx_serial_data_ch3.rx_serial_data
			x_rx_seriallpbken_ch0_rx_seriallpbken           => CONNECTED_TO_x_rx_seriallpbken_ch0_rx_seriallpbken,           --      x_rx_seriallpbken_ch0.rx_seriallpbken
			x_rx_seriallpbken_ch1_rx_seriallpbken           => CONNECTED_TO_x_rx_seriallpbken_ch1_rx_seriallpbken,           --      x_rx_seriallpbken_ch1.rx_seriallpbken
			x_rx_seriallpbken_ch2_rx_seriallpbken           => CONNECTED_TO_x_rx_seriallpbken_ch2_rx_seriallpbken,           --      x_rx_seriallpbken_ch2.rx_seriallpbken
			x_rx_seriallpbken_ch3_rx_seriallpbken           => CONNECTED_TO_x_rx_seriallpbken_ch3_rx_seriallpbken,           --      x_rx_seriallpbken_ch3.rx_seriallpbken
			x_rx_is_lockedtoref_ch0_rx_is_lockedtoref       => CONNECTED_TO_x_rx_is_lockedtoref_ch0_rx_is_lockedtoref,       --    x_rx_is_lockedtoref_ch0.rx_is_lockedtoref
			x_rx_is_lockedtoref_ch1_rx_is_lockedtoref       => CONNECTED_TO_x_rx_is_lockedtoref_ch1_rx_is_lockedtoref,       --    x_rx_is_lockedtoref_ch1.rx_is_lockedtoref
			x_rx_is_lockedtoref_ch2_rx_is_lockedtoref       => CONNECTED_TO_x_rx_is_lockedtoref_ch2_rx_is_lockedtoref,       --    x_rx_is_lockedtoref_ch2.rx_is_lockedtoref
			x_rx_is_lockedtoref_ch3_rx_is_lockedtoref       => CONNECTED_TO_x_rx_is_lockedtoref_ch3_rx_is_lockedtoref,       --    x_rx_is_lockedtoref_ch3.rx_is_lockedtoref
			x_rx_is_lockedtodata_ch0_rx_is_lockedtodata     => CONNECTED_TO_x_rx_is_lockedtodata_ch0_rx_is_lockedtodata,     --   x_rx_is_lockedtodata_ch0.rx_is_lockedtodata
			x_rx_is_lockedtodata_ch1_rx_is_lockedtodata     => CONNECTED_TO_x_rx_is_lockedtodata_ch1_rx_is_lockedtodata,     --   x_rx_is_lockedtodata_ch1.rx_is_lockedtodata
			x_rx_is_lockedtodata_ch2_rx_is_lockedtodata     => CONNECTED_TO_x_rx_is_lockedtodata_ch2_rx_is_lockedtodata,     --   x_rx_is_lockedtodata_ch2.rx_is_lockedtodata
			x_rx_is_lockedtodata_ch3_rx_is_lockedtodata     => CONNECTED_TO_x_rx_is_lockedtodata_ch3_rx_is_lockedtodata,     --   x_rx_is_lockedtodata_ch3.rx_is_lockedtodata
			x_tx_coreclkin_ch0_clk                          => CONNECTED_TO_x_tx_coreclkin_ch0_clk,                          --         x_tx_coreclkin_ch0.clk
			x_tx_coreclkin_ch1_clk                          => CONNECTED_TO_x_tx_coreclkin_ch1_clk,                          --         x_tx_coreclkin_ch1.clk
			x_tx_coreclkin_ch2_clk                          => CONNECTED_TO_x_tx_coreclkin_ch2_clk,                          --         x_tx_coreclkin_ch2.clk
			x_tx_coreclkin_ch3_clk                          => CONNECTED_TO_x_tx_coreclkin_ch3_clk,                          --         x_tx_coreclkin_ch3.clk
			x_rx_coreclkin_ch0_clk                          => CONNECTED_TO_x_rx_coreclkin_ch0_clk,                          --         x_rx_coreclkin_ch0.clk
			x_rx_coreclkin_ch1_clk                          => CONNECTED_TO_x_rx_coreclkin_ch1_clk,                          --         x_rx_coreclkin_ch1.clk
			x_rx_coreclkin_ch2_clk                          => CONNECTED_TO_x_rx_coreclkin_ch2_clk,                          --         x_rx_coreclkin_ch2.clk
			x_rx_coreclkin_ch3_clk                          => CONNECTED_TO_x_rx_coreclkin_ch3_clk,                          --         x_rx_coreclkin_ch3.clk
			x_tx_clkout_ch0_clk                             => CONNECTED_TO_x_tx_clkout_ch0_clk,                             --            x_tx_clkout_ch0.clk
			x_tx_clkout_ch1_clk                             => CONNECTED_TO_x_tx_clkout_ch1_clk,                             --            x_tx_clkout_ch1.clk
			x_tx_clkout_ch2_clk                             => CONNECTED_TO_x_tx_clkout_ch2_clk,                             --            x_tx_clkout_ch2.clk
			x_tx_clkout_ch3_clk                             => CONNECTED_TO_x_tx_clkout_ch3_clk,                             --            x_tx_clkout_ch3.clk
			x_rx_clkout_ch0_clk                             => CONNECTED_TO_x_rx_clkout_ch0_clk,                             --            x_rx_clkout_ch0.clk
			x_rx_clkout_ch1_clk                             => CONNECTED_TO_x_rx_clkout_ch1_clk,                             --            x_rx_clkout_ch1.clk
			x_rx_clkout_ch2_clk                             => CONNECTED_TO_x_rx_clkout_ch2_clk,                             --            x_rx_clkout_ch2.clk
			x_rx_clkout_ch3_clk                             => CONNECTED_TO_x_rx_clkout_ch3_clk,                             --            x_rx_clkout_ch3.clk
			x_tx_parallel_data_ch0_tx_parallel_data         => CONNECTED_TO_x_tx_parallel_data_ch0_tx_parallel_data,         --     x_tx_parallel_data_ch0.tx_parallel_data
			x_tx_parallel_data_ch1_tx_parallel_data         => CONNECTED_TO_x_tx_parallel_data_ch1_tx_parallel_data,         --     x_tx_parallel_data_ch1.tx_parallel_data
			x_tx_parallel_data_ch2_tx_parallel_data         => CONNECTED_TO_x_tx_parallel_data_ch2_tx_parallel_data,         --     x_tx_parallel_data_ch2.tx_parallel_data
			x_tx_parallel_data_ch3_tx_parallel_data         => CONNECTED_TO_x_tx_parallel_data_ch3_tx_parallel_data,         --     x_tx_parallel_data_ch3.tx_parallel_data
			x_rx_parallel_data_ch0_rx_parallel_data         => CONNECTED_TO_x_rx_parallel_data_ch0_rx_parallel_data,         --     x_rx_parallel_data_ch0.rx_parallel_data
			x_rx_parallel_data_ch1_rx_parallel_data         => CONNECTED_TO_x_rx_parallel_data_ch1_rx_parallel_data,         --     x_rx_parallel_data_ch1.rx_parallel_data
			x_rx_parallel_data_ch2_rx_parallel_data         => CONNECTED_TO_x_rx_parallel_data_ch2_rx_parallel_data,         --     x_rx_parallel_data_ch2.rx_parallel_data
			x_rx_parallel_data_ch3_rx_parallel_data         => CONNECTED_TO_x_rx_parallel_data_ch3_rx_parallel_data,         --     x_rx_parallel_data_ch3.rx_parallel_data
			f_tx_analogreset_ch0_tx_analogreset             => CONNECTED_TO_f_tx_analogreset_ch0_tx_analogreset,             --       f_tx_analogreset_ch0.tx_analogreset
			f_tx_analogreset_ch1_tx_analogreset             => CONNECTED_TO_f_tx_analogreset_ch1_tx_analogreset,             --       f_tx_analogreset_ch1.tx_analogreset
			f_tx_digitalreset_ch0_tx_digitalreset           => CONNECTED_TO_f_tx_digitalreset_ch0_tx_digitalreset,           --      f_tx_digitalreset_ch0.tx_digitalreset
			f_tx_digitalreset_ch1_tx_digitalreset           => CONNECTED_TO_f_tx_digitalreset_ch1_tx_digitalreset,           --      f_tx_digitalreset_ch1.tx_digitalreset
			f_tx_analogreset_stat_ch0_tx_analogreset_stat   => CONNECTED_TO_f_tx_analogreset_stat_ch0_tx_analogreset_stat,   --  f_tx_analogreset_stat_ch0.tx_analogreset_stat
			f_tx_analogreset_stat_ch1_tx_analogreset_stat   => CONNECTED_TO_f_tx_analogreset_stat_ch1_tx_analogreset_stat,   --  f_tx_analogreset_stat_ch1.tx_analogreset_stat
			f_tx_digitalreset_stat_ch0_tx_digitalreset_stat => CONNECTED_TO_f_tx_digitalreset_stat_ch0_tx_digitalreset_stat, -- f_tx_digitalreset_stat_ch0.tx_digitalreset_stat
			f_tx_digitalreset_stat_ch1_tx_digitalreset_stat => CONNECTED_TO_f_tx_digitalreset_stat_ch1_tx_digitalreset_stat, -- f_tx_digitalreset_stat_ch1.tx_digitalreset_stat
			f_tx_cal_busy_ch0_tx_cal_busy                   => CONNECTED_TO_f_tx_cal_busy_ch0_tx_cal_busy,                   --          f_tx_cal_busy_ch0.tx_cal_busy
			f_tx_cal_busy_ch1_tx_cal_busy                   => CONNECTED_TO_f_tx_cal_busy_ch1_tx_cal_busy,                   --          f_tx_cal_busy_ch1.tx_cal_busy
			f_tx_serial_data_ch0_tx_serial_data             => CONNECTED_TO_f_tx_serial_data_ch0_tx_serial_data,             --       f_tx_serial_data_ch0.tx_serial_data
			f_tx_serial_data_ch1_tx_serial_data             => CONNECTED_TO_f_tx_serial_data_ch1_tx_serial_data,             --       f_tx_serial_data_ch1.tx_serial_data
			f_tx_coreclkin_ch0_clk                          => CONNECTED_TO_f_tx_coreclkin_ch0_clk,                          --         f_tx_coreclkin_ch0.clk
			f_tx_coreclkin_ch1_clk                          => CONNECTED_TO_f_tx_coreclkin_ch1_clk,                          --         f_tx_coreclkin_ch1.clk
			f_tx_clkout_ch0_clk                             => CONNECTED_TO_f_tx_clkout_ch0_clk,                             --            f_tx_clkout_ch0.clk
			f_tx_clkout_ch1_clk                             => CONNECTED_TO_f_tx_clkout_ch1_clk,                             --            f_tx_clkout_ch1.clk
			f_tx_parallel_data_ch0_tx_parallel_data         => CONNECTED_TO_f_tx_parallel_data_ch0_tx_parallel_data,         --     f_tx_parallel_data_ch0.tx_parallel_data
			f_tx_parallel_data_ch1_tx_parallel_data         => CONNECTED_TO_f_tx_parallel_data_ch1_tx_parallel_data          --     f_tx_parallel_data_ch1.tx_parallel_data
		);

