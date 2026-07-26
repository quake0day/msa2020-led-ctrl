# 3 PCIE_DMA

**状态：🚧 开发中（占位）**

独立的 **PCIe DMA 最小实验** —— 只做 FPGA↔主机的 PCIe DMA 数据搬运，
不含 Corundum 全套 NIC（那是 [5](../5_Corundum_fork_on_MSA2020/)）。

## 目标

- Stratix 10 H/L-tile PCIe 硬核（Gen3 x16）最小例化 + Avalon-ST / AXI 桥
- 简单的 DMA 引擎（主机内存 ↔ 板载片上 RAM）
- 主机侧最小驱动 / 用户态程序做读写吞吐验证

## 板卡资源（已备）

- PCIe Gen3 x16 引脚：`TX BB34..AK42` / `RX AV30..AJ36` / refclk `AM34/AM33` /
  perst `AC26`（见顶层 README 或 5 的 PINDEF 提取）。
- PCIe 硬核 IP 生成方式见 5 的 `ip/pcie.tcl`（`chosen_devkit_hwtcl=NONE`，
  本板器件 `1SG280LN2F43E2VG`）。

## 现状

尚未开工。可从 5 的 PCIe 硬核 + 一个精简 DMA 数据通路起步，
比移植整套 mqnic 轻量得多，适合先跑通 PCIe DMA 基本功能。
