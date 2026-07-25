# 阶段4 — Corundum mqnic 移植到 A-2020（进行中）

## 已完成的基础（本会话）

- **确认可行性**: `fpga_25g` 变体**不需外部内存**(0 个 HBM/DDR 端口, 仅片上
  32KB TX/RX RAM) —— A-2020 没有 520N_MX 的 HBM 不成问题。
- **A-2020 PCIe 引脚已提取**(PINDEF): Gen3 **x16**, `PCIE_Tx/Rx[15:0]`,
  refclk `AM34/AM33`, perst `AC26`。
- **全部 9 个 IP 已按 A-2020 器件(1SG280LN2F43E2VG)生成**于 `ip/`:
  - `pcie.ip` (altera_pcie_s10_hip_ast, H-tile PCIe 硬核 — A-2020 是 HSSI_CRETE2P/H-tile)
  - `iopll_100mhz.ip` / `ref_div.ip` / `reset_release.ip`
  - `eth_xcvr_gxt/gxt_pll/gxt_buf/gx/gx_pll/reset.ip`(**含 anlg_link=sr 修正**,
    与已验证的阶段1 收发器同源)
- **收发器层已验证可跑**: 阶段1 的 `06_qsfp_xcvr` 就是 mqnic 的 PHY 层
  (eth_xcvr_phy_quad_wrapper),4×25.78G 已在硬件锁定。

## 剩余移植步骤（较大工作量，需连主机 PCIe 槽验证）

1. **改写板级顶层** `rtl/fpga.v`(源自 520N_MX, 1667 行): 去掉 HBM/多 QSFP/
   usr_refclk 等 520N_MX 专属外设, 只留 A-2020 有的: PCIe x16、QSFP0、clock_100。
   引脚换成 A-2020(上方 PCIe 表 + QSFP0 AG40 等 + refclk AD34)。
2. **应用三联组时钟分配修正**到 quad wrapper(已在阶段1 验证: master→下三联组
   data[0],[3] / buffer→上三联组 data[1],[2]; 但 mqnic 用 4 独立 PHY, 直接沿用
   阶段1 的 06_qsfp_xcvr/rtl 版即可)。
3. **源文件清单**(照搬 Corundum Makefile SYN_FILES): 5 板级 rtl + 44
   `fpga/common/rtl/*.v`(mqnic 核) + 69 `fpga/lib/*/rtl/*.v`。全在
   `H:\led_ctrl\05_corundum\corundum` 树里(符号链接在 Windows 断了, 用真实路径)。
4. **mqnic 参数**: 见 520N_MX `fpga/config.tcl`(队列数、RAM 大小、BAR 等)。
5. **PCIe SDC** + 时序约束(照搬 520N_MX fpga.sdc 的 PCIe/xcvr 部分)。
6. 编译 → 调试(端口/参数不匹配等) → 得 `.sof`。
7. **验证**: 需把板卡插进**主机 PCIe 槽**, 加载 mqnic 驱动(mqnic.ko)枚举网卡。
   当前 JTAG 台面连接**无法验证 PCIe 枚举** —— 这一步等物理环境。

## 关键判断

A-2020 的 QSFP0 四条 lane 接到**物理通道 0,1,3,4(非连续, 跳过 ch2)**, 这是为
**4×25G 独立 lane** 设计的(正是 mqnic 的用法), 不是 bonded 100G。所以 Corundum
(4×25G)是这块板 QSFP 的**天然归宿**, 收发器基础已就绪, 顶层移植是主要剩余工作。
