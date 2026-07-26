// =====================================================================
// MSA-2020 独立 PCIe 最小实验 (Gen3x8, Avalon-MM)
//   主机把 FPGA 的 256KB 片内 RAM 映射进 BAR0, 经 PCIe 直接读写 ——
//   FPGA <-> 主机的 PCIe 数据搬运基座 (host-driven / PIO over PCIe)。
//   数据通路: 主机 mmap(BAR0) -> PCIe 硬核 rxm_bar0 -> 片内 RAM。
//
//   LED (板载绿灯, 低有效):
//     grn[0] = pcie_perstn (亮 = 主机已释放 PERST#, 槽位上电/主机在)
//     grn[1] = coreclk 心跳 (闪 = PCIe 硬核 coreclkout_hip 在跑, PLL 已锁)
// =====================================================================
`default_nettype none
module pcie_dma (
    input  wire        pcie_refclk,   // 100MHz HCSL 参考时钟 (AM34)
    input  wire        pcie_perstn,   // PCIe PERST# (AC26)
    input  wire [7:0]  pcie_rx,       // PCIe RX lane 0..7
    output wire [7:0]  pcie_tx,       // PCIe TX lane 0..7
    output wire [1:0]  led_user_grn   // 状态灯 (低有效)
);
    wire coreclk;   // 硬核 coreclkout_hip (Gen3x8 = 250MHz)

    // ---- coreclk 心跳分频 (自由运行, 证明硬核在时钟) ----
    reg [26:0] hb = 27'd0;
    always @(posedge coreclk) hb <= hb + 27'd1;

    assign led_user_grn[0] = ~pcie_perstn;   // 亮 = 已出 PERST#
    assign led_user_grn[1] = ~hb[26];        // 闪 = coreclk 心跳

    pcie_dma_sys u_sys (
        .refclk_clk         (pcie_refclk),
        .npor_npor          (1'b1),
        .npor_pin_perst     (pcie_perstn),
        .coreclk_clk        (coreclk),
        .hip_serial_rx_in0  (pcie_rx[0]),
        .hip_serial_rx_in1  (pcie_rx[1]),
        .hip_serial_rx_in2  (pcie_rx[2]),
        .hip_serial_rx_in3  (pcie_rx[3]),
        .hip_serial_rx_in4  (pcie_rx[4]),
        .hip_serial_rx_in5  (pcie_rx[5]),
        .hip_serial_rx_in6  (pcie_rx[6]),
        .hip_serial_rx_in7  (pcie_rx[7]),
        .hip_serial_tx_out0 (pcie_tx[0]),
        .hip_serial_tx_out1 (pcie_tx[1]),
        .hip_serial_tx_out2 (pcie_tx[2]),
        .hip_serial_tx_out3 (pcie_tx[3]),
        .hip_serial_tx_out4 (pcie_tx[4]),
        .hip_serial_tx_out5 (pcie_tx[5]),
        .hip_serial_tx_out6 (pcie_tx[6]),
        .hip_serial_tx_out7 (pcie_tx[7])
    );
endmodule
`default_nettype wire
