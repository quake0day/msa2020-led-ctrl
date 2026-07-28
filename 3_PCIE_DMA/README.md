# 3 PCIE_DMA — 独立 PCIe 最小实验

**状态：✅ BAR 读写已在真实硬件跑通**（主机 mmap 256KB 片内 RAM，full-256KB 唯一值全通、
字节使能通、边界通；2026-07-27，板卡在主机 PCIe 槽）

独立、最小的 **PCIe 数据搬运** 实验：把 FPGA 的 **256KB 片内 RAM 映射进 BAR0**，
主机经 PCIe 直接读写 —— 即 FPGA↔主机的 PCIe 数据通道基座。
不含 Corundum 全套 NIC（那是 [5](../5_Corundum_fork_on_MSA2020/)）。

## 这是什么（关于"DMA"的诚实说明）

本工程用 **Stratix 10 PCIe 硬核的 Avalon-ST 原始 TLP 接口**
（`altera_pcie_s10_hip_ast`，**Gen2 x8**）+ 一段自包含的 TLP 目标逻辑，把 BAR0
读写请求译成 AXI-Lite 落到片内 RAM：

```
主机 mmap(BAR0) ─PCIe Gen2x8─▶ [PCIe 硬核 hip_ast] ─Avalon-ST TLP─▶
   [Corundum pcie_s10_if] ─TLP─▶ [pcie_axil_master_minimal] ─AXI-Lite─▶ [256KB 片内 RAM]
```

- 这是 **主机驱动 (host-driven / PIO over PCIe)** 的 BAR 映射内存，是"PCIe 数据
  搬运"的最小、最稳基座，主机侧一条 `mmap`+读写即可验证。
- **为什么不用 avmm 桥**：早期版本用 `altera_pcie_s10_hip_avmm_bridge`，但 avmm 桥的
  BAR→完成路由依赖 qsys 互连生成的 `slave_address_map_0`，独立例化（无 qsys 顶层系统）
  时无法定义，完成 TLP 回不去主机 → 读全 `0xffffffff`。改用 **hip_ast 原始 TLP 接口 +
  Corundum 已验证的 TLP 栈**，完全自包含、不依赖 qsys 互连。
- **总线主控 (bus-master) 描述符 DMA 引擎**：直接看 **项目 5 Corundum**（完整 mqnic DMA/NIC）。
  本最小实验刻意不含，保持可读、可移植。

## 器件与地址

- 器件 `1SG280LN2F43E2VG`，Quartus **23.3**（`H:\fpga`，见 [[msa2020-quartus-toolchain]]）。
- PCIe **VID 0x1234 / DID 0x1002**（与 5 Corundum 区分，便于枚举时分辨）。
- BAR0：64-bit prefetchable，**256KB**（addr_width=18）→ 64K×32-bit 片内 RAM。
- 引脚：**x8 用 lane 0..7**（`TX BB34.. / RX AV30..`，refclk `AM34` HCSL，perst `AC26`）。
  x8 端点插 x16 槽自动协商到 x8。链路实测 Gen2 (5GT/s) x8。

## 文件

采用与 [5](../5_Corundum_fork_on_MSA2020/) 相同的**独立 IP + Verilog 手连**模式
（不用 Platform Designer 顶层系统——无头环境下 qsys 系统的叶子 IP 生成不稳）：

| 文件 | 说明 |
|------|------|
| `ip/pcie.ip` (+`ip/pcie.tcl`) | PCIe 硬核 **hip_ast**（Gen2x8 / 256-bit AST / BAR0 256KB / VID 0x1234 DID 0x1002）|
| `ip/reset_release.ip` | Stratix 10 复位释放 → `ninit_done`（复用自 5）|
| `ip/iopll_100mhz.ip` | usr_refclk0 → 100MHz + `sync_reset` → `npor`（复用自 5 的复位序列）|
| `rtl/pcie_dma.v` | 顶层：hip_ast → `pcie_s10_if` → `pcie_axil_master_minimal` → `axil_ram`(256KB)，DMA/MSI 全 tie-off，pipe/sim 端口按硬件模式置 0，serial → PCIe 引脚 + 观测 LED |
| Corundum TLP 栈 | `pcie_s10_if{,_rx,_tx}.v` / `pcie_s10_cfg.v` / `pcie_tlp_*.v` / `pcie_axil_master_minimal.v` / `axil_ram.v`（引自 `05_corundum`）|
| `host/` | 主机侧脚本：`bar_mem.py`（mmap 读写）、`pcie_fix_bridge_window.sh`（关键，见下）、`pcie_disable_fatal_err.sh` |
| `pcie_dma.qsf` / `.qpf` / `.sdc` | Quartus 工程（含板卡 VID 供电块，勿改；无 CVP_CONFDONE 便于 JTAG 烧录）|

顶层观测灯（板载绿灯，低有效）：`grn[0]` = `~rxreq_seen`（亮=BAR 请求已进 TLP 栈）；
`grn[1]` = `~txcpl_seen`（亮=栈已形成完成 TLP）。

## 编译（无头即可，0 error / 时序通过）

```bash
cd 3_PCIE_DMA
export QUARTUS_ROOTDIR="H:\fpga\quartus"          # 23.3, 有 S10 器件
"$QUARTUS_ROOTDIR/bin64/quartus_ipgenerate" pcie_dma --synthesis=verilog --generate_project_ip_files
"$QUARTUS_ROOTDIR/bin64/quartus_sh" --flow compile pcie_dma   # -> output_files/pcie_dma.sof
```

> **编译坑**：把 `ipgenerate` 和 `compile` 链在一条命令里跑，会让汇编器报"file changed
> since last compile"→ 内部崩溃（Error 23031）。清掉 `qdb/ incremental_db/ output_files/`
> 重新全量编译即可。其余工具链坑见 [[msa2020-quartus-toolchain]]。

## 烧录 + 主机侧验证

**烧录**：板卡必须**在主机 PCIe 槽内**（refclk 就绪）才能配 SRAM；台面 JTAG 无 refclk 会
报 "Device is in configuration state" 失败。

```bash
quartus_pgm -c "Microsoft Catapult (64)" -m JTAG -o "P;output_files/pcie_dma.sof"
```

**验证**（Linux，详见 [`HOST_VALIDATION.md`](HOST_VALIDATION.md)）：

```bash
# 改了 BAR 需重新枚举
echo 1 | sudo tee /sys/bus/pci/devices/0000:01:00.0/remove
echo 1 | sudo tee /sys/bus/pci/rescan
# ⚠️ 关键：remove+rescan 会搞坏上游桥的可预取窗口, 必须修复(否则读全 0xffffffff)
sudo bash host/pcie_fix_bridge_window.sh
# 读写回环
BDF=$(lspci -d 1234:1002 | cut -d' ' -f1)
sudo python3 host/bar_mem.py 0000:$BDF 0x0 0xDEADBEEF && sudo python3 host/bar_mem.py 0000:$BDF 0x0
```

> **最大的坑**：曾长时间 BAR 读全 `0xffffffff`——其实**不是 FPGA 的锅**，是 `remove+rescan`
> 把上游桥 `00:01.0` 的可预取窗口留成了 base>limit（禁用）+ upper32=0，内存 TLP 根本
> 没转发到 FPGA（决定性证据：读后设备/根口 AER 全清，无 UnsupReq/无完成超时）。
> `host/pcie_fix_bridge_window.sh` 用 setpci 重设窗口覆盖 BAR 即修复。冷启动 BIOS 会正常
> 建窗口，只有热式 remove+rescan 触发此坑。完整根因见 HOST_VALIDATION.md。
