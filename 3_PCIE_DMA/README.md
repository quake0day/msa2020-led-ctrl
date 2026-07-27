# 3 PCIE_DMA — 独立 PCIe 最小实验

**状态：✅ 已编译出 `.sof`（0 error，时序通过）；⏳ BAR 读写待插主机 PCIe 槽验证**

独立、最小的 **PCIe 数据搬运** 实验：把 FPGA 的 **256KB 片内 RAM 映射进
BAR0**，主机经 PCIe 直接读写 —— 即 FPGA↔主机的 PCIe 数据通道基座。
不含 Corundum 全套 NIC（那是 [5](../5_Corundum_fork_on_MSA2020/)）。

## 这是什么（关于"DMA"的诚实说明）

本工程用 **Stratix 10 PCIe 硬核的 Avalon-MM 桥**（`altera_pcie_s10_hip_avmm_bridge`，
**Gen3 x8**），把 BAR0 的读写请求经 `rxm_bar0`（32-bit Avalon-MM 主）直接落到
片内 RAM：

```
主机 mmap(BAR0) ──PCIe Gen3x8──▶ [PCIe 硬核 avmm 桥] ──rxm_bar0(32b)──▶ [256KB 片内 RAM]
```

- 这是 **主机驱动 (host-driven / PIO over PCIe)** 的 BAR 映射内存，是"PCIe 数据
  搬运"的最小、最稳基座，主机侧一条 `mmap`+读写即可验证。
- **总线主控 (bus-master) 的描述符 DMA 引擎**：同一颗硬核支持打开内置硬核 DMA
  （`dma_enabled=1`，另出读/写数据搬运器 + 描述符控制器），或直接看 **项目 5
  Corundum** —— 那是完整的 mqnic DMA/NIC。本最小实验刻意不含这套，保持可读、可移植。

## 器件与地址

- 器件 `1SG280LN2F43E2VG`，Quartus **23.3**（`H:\fpga`，见 [[msa2020-quartus-toolchain]]）。
- PCIe **VID 0x1234 / DID 0x1002**（与 5 Corundum 的 0x1001 区分，便于枚举时分辨）。
- BAR0：64-bit prefetchable，**256KB**（addr_width=18）→ 64K×32-bit 片内 RAM。
- 引脚：**Gen3 x8 用 lane 0..7**（`TX BB34.. / RX AV30..`，refclk `AM34` HCSL，
  perst `AC26`）。x8 端点插 x16 槽会自动协商到 x8。

## 文件

采用与 [5](../5_Corundum_fork_on_MSA2020/) 相同的**独立 IP + Verilog 手连**模式
（不用 Platform Designer 顶层系统——无头环境下 qsys 系统的叶子 IP 生成不稳）：

| 文件 | 说明 |
|------|------|
| `ip/pcie.ip` (+`ip/pcie.tcl`) | PCIe 硬核 avmm 桥（Gen3x8 / BAR0 256KB / 32-bit 非突发 rxm / 无 DMA / VID 0x1234 DID 0x1002）|
| `ip/reset_release.ip` | Stratix 10 复位释放 → `ninit_done`（复用自 5）|
| `rtl/pcie_dma.v` | 顶层：例化 `pcie` + `reset_release`，`rxm_bar0(32b)` → 推断 256KB 片内 RAM，pipe/sim 端口按硬件模式全置 0（同 5 的 `fpga.v`），serial → PCIe 引脚 + 状态 LED |
| `gen_top.py` | 由 `ip/pcie/synth/pcie.v` 端口表自动生成 `rtl/pcie_dma.v`（改 IP 配置后重跑）|
| `pcie_dma.qsf` / `.qpf` / `.sdc` | Quartus 工程（含板卡 VID 供电块，勿改；无 CVP_CONFDONE 便于 JTAG 烧录）|

顶层状态灯（板载绿灯，低有效）：`grn[0]` = `pcie_perstn`（亮=主机已释放 PERST#）；
`grn[1]` = `coreclk` 心跳（闪=PCIe 硬核 `coreclkout_hip` 在跑、PLL 已锁）。

## 编译（无头即可，已验证 0 error / 时序通过）

```bash
cd 3_PCIE_DMA
export QUARTUS_ROOTDIR="H:\fpga\quartus"          # 23.3, 有 S10 器件
# 1) 生成 IP HDL（pcie 硬核+收发器、reset_release）
"$QUARTUS_ROOTDIR/bin64/quartus_ipgenerate" pcie_dma --synthesis=verilog --generate_project_ip_files
# 2) 全流程编译 -> output_files/pcie_dma.sof
"$QUARTUS_ROOTDIR/bin64/quartus_sh" --flow compile pcie_dma
```

实测资源极小：3298 ALM(<1%) + 133 M20K(256KB) + 10 PLL。改 PCIe 配置就编辑
`ip/pcie.tcl` 重新生成 `ip/pcie.ip`，再 `python gen_top.py` 重生顶层。
从 `.sof` 用 `quartus_pfg` 生成 `.jic` 烧录（VID/供电块已按官方 blink 配好）。

> 踩坑记录见 [[msa2020-quartus-toolchain]]：无头 `qsys-script` 存盘会把 qsys **系统**
> 的叶子转成 Generic Component（无 HDL），所以走独立 `.ip`；`qsys-script` 偶发"挂死"
> 其实是残留 java 进程锁——杀掉 java 重跑即可。

台面（JTAG）烧录后：`grn[1]` 心跳闪 = 硬核时钟起来了。**BAR 读写必须插主机
PCIe 槽**才能测（见下）。

## 主机侧验证

见 [`HOST_VALIDATION.md`](HOST_VALIDATION.md)。要点：插主机 PCIe 槽后

- **Linux**（推荐）：`lspci -d 1234:1002 -v` 看到 256KB BAR0；用 `pcimem` 对
  `resource0` 做 32-bit 读写回环，验证 PCIe↔FPGA 数据通路。
- **Windows**：设备管理器可见 `VEN_1234&DEV_1002`（确认枚举）；BAR 读写需内核
  驱动，Windows 无现成用户态 mmap，建议用 Linux 实测。
