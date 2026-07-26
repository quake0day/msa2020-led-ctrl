# 3 PCIE_DMA — 独立 PCIe 最小实验

**状态：🧩 设计完成，待生成叶子 IP HDL 后编译**（详见下方"生成与编译"）

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

| 文件 | 说明 |
|------|------|
| `make_qsys.tcl` | Platform Designer 系统 `pcie_dma_sys` 构建脚本：avmm 桥 + 256KB 片内 RAM + 时钟/复位桥 + 复位释放 |
| `ip/pcie.tcl` | 单独的 avmm 桥 IP 配置（Gen3x8/BAR0/非突发 rxm/无 DMA）参考 |
| `rtl/pcie_dma.v` | 顶层：例化 `pcie_dma_sys`，接 PCIe 串行/refclk/perst + 状态 LED |
| `pcie_dma.qsf` / `.qpf` / `.sdc` | Quartus 工程（含板卡 VID 供电块，勿改；无 CVP_CONFDONE 便于 JTAG 烧录）|

顶层状态灯（板载绿灯，低有效）：`grn[0]` = `pcie_perstn`（亮=主机已释放 PERST#）；
`grn[1]` = `coreclk` 心跳（闪=PCIe 硬核 coreclkout_hip 在跑、PLL 已锁）。

## 生成与编译

> ⚠️ **本机无头限制**：这套无头 Quartus 环境里 `qsys-script` 存盘会把叶子组件
> 转成 Generic Component（无 HDL），`qsys-generate`/`quartus_ipgenerate` 只能生成
> 互连、生成不出 `pcie`/`onchip_ram`/桥 等叶子 IP 的 HDL（报 *undefined entity
> pcie_dma_sys_pcie_N*）。项目 2/5 的叶子 `ip/*.ip` 都是**用 Platform Designer
> GUI 生成**的。细节见 [[msa2020-quartus-toolchain]]。

在**装了 GUI 的 Quartus 23.3** 里完成生成即可编译（`pcie_dma_sys.qsys` 已是
真实组件系统，非 Generic 占位）：

1. 打开 Platform Designer，`File→Open` 载入 **`pcie_dma_sys.qsys`**（含 avmm 桥 +
   256KB 片内 RAM + 时钟/复位桥 + 复位释放，5 个真实 IP），点 **Generate HDL**
   —— 会在 `ip/pcie_dma_sys/` 下生成各叶子 IP 的 HDL（含 PCIe 硬核 + 收发器）。
   （想改配置就重跑 `make_qsys.tcl`：GUI Tcl Console `source make_qsys.tcl`。）
2. `quartus_sh --flow compile pcie_dma`（或 GUI 编译）→ `output_files/pcie_dma.sof`。
3. 从 .sof 生成 .jic 烧录（VID/供电块已按官方 blink 配好）。

台面（JTAG）烧录后：`grn[1]` 心跳闪 = 硬核时钟起来了。**BAR 读写必须插主机
PCIe 槽**才能测（见下）。

## 主机侧验证

见 [`HOST_VALIDATION.md`](HOST_VALIDATION.md)。要点：插主机 PCIe 槽后

- **Linux**（推荐）：`lspci -d 1234:1002 -v` 看到 256KB BAR0；用 `pcimem` 对
  `resource0` 做 32-bit 读写回环，验证 PCIe↔FPGA 数据通路。
- **Windows**：设备管理器可见 `VEN_1234&DEV_1002`（确认枚举）；BAR 读写需内核
  驱动，Windows 无现成用户态 mmap，建议用 Linux 实测。
