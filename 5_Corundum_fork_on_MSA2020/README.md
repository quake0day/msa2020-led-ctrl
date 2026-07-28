# 阶段4 — Corundum mqnic 移植到 A-2020

## ★ 状态: 已在真实硬件跑通 (2026-07-27) ★

完整 NIC (PCIe 硬核 + mqnic DMA 核 + QSFP0 收发器) 在 A-2020 上编译通过并
**在 Ubuntu 主机 (kernel 7.0.0, 板卡在 PCIe 槽) 完整验证**: 枚举为
Ethernet controller `1234:1001`, mqnic 驱动 probe 通过, 建出 `/dev/mqnic0` +
**两个网口** `enp1s0np0/np1`, DMA 收发队列就绪、PTP 时钟在跑、4 条 lane 时钟都活。
唯一未测=光口实际收发包(需插 QSFP 模块/环回件)。**完整验证 + kernel 7.0 驱动移植补丁
见 [HOST_VALIDATION.md](HOST_VALIDATION.md)**, 补丁源码在 `driver_mqnic_kernel7/`,
主机一键编译加载脚本 `host/build_load_mqnic.sh`。工程 qsfp_mqnic.qsf。

**移植踩坑记录 (从 4 QSFP 缩到 1 + A-2020, ~8 轮编译)**:
1. PCIe IP devkit: 用 `chosen_devkit_hwtcl {NONE}`(本板 1SG280LN2 只认 L-Tile
   devkit, 选 H-Tile 报 out of range 并强改器件)。
2. Verilog 源清单: Makefile 第一行 `SYN_FILES = rtl/fpga.v` 用 `=` 不是 `+=`,
   grep `+=` 会漏掉顶层 fpga.v。
3. **Windows 路径**: qsf 里 Corundum 源必须用 `H:/led_ctrl/...` 不能用
   git-bash 的 `/h/...`(否则 114 个文件全 "Can't analyze", 整个 mqnic 核变
   blackbox → "cannot connect unsized constant 0")。
4. PCIe IP 版本差异: 23.3 IP 无 `app_msi_func_num`/`app_err_func_num` 端口
   (单功能配置), 顶层实例化要删掉这些连接。
5. 4→1 缩减后末尾端口留下悬空逗号 (port,\n\n); ) 要删。
6. 引脚同 bank 电压冲突: pcie_perstn(AC26) 与 I2C(bank 6A) 同 bank, 都设
   3.0-V LVTTL。
7. **收发器时钟-三联组映射**: mqnic 引脚按三联组连续排 (tx[0,1]=下 ch0,1 /
   tx[2,3]=上 ch3,4), 用 Corundum **默认** quad wrapper 映射 (phy_1,2→clk[0] /
   phy_3,4→clk[1]); 别套阶段1 的 06_qsfp_xcvr 那版(引脚顺序不同, 会错位)。
8. SDC 要补 ref_div clock_div4 / iopll_100mhz / sync_reset 的异步约束。

---
（以下为移植前的规划记录）

# 阶段4 — Corundum mqnic 移植到 A-2020（原规划）

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

## 已组装完成（本会话追加）

- **完整工程已搭好**: `qsfp_mqnic.qsf` = 器件/VID + **10 个 IP** + **118 个源文件**
  (Corundum common/lib, 路径已解析: `lib/axis`→`lib/eth/lib/axis`,
  `rtl/common`→`fpga/common/rtl`)。`sources_common.qsf` 是源清单片段。
- `fpga_25g` 变体确认**无 HBM/esram/DDR 端口**(已是纯片上 RAM), 无内存移植负担。
- 只差顶层 `rtl/fpga.v`(1667行)+ `fpga_core.v` 的 **4 QSFP→1、换 A-2020 引脚**。

## 剩余移植步骤（较大工作量，需连主机 PCIe 槽验证）

**核心剩余 = fpga.v/fpga_core.v 从 4 QSFP 缩到 1(QSFP0)+ 换 A-2020 引脚**:
fpga.v 端口 = usr_refclk0/led/i2c/pcie/qsfp0-3/qsfp_irq_n; 需删 qsfp1/2/3
(共 ~477 处引用)、每个 QSFP 是一个 quad wrapper(删 3 个)、fpga_core IF_COUNT 2→1。
收发器 quad wrapper 用 06_qsfp_xcvr 的已验证版(三联组时钟分配 + anlg_link=sr)。

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
