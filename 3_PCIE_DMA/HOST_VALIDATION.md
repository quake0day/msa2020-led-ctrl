# 3 PCIE_DMA 主机侧验证

设计：PCIe Gen3 x8 端点，**BAR0 = 256KB 片内 RAM**，VID `0x1234` / DID `0x1002`。
主机把 BAR0 映射进地址空间后，直接 32-bit 读写即验证 PCIe↔FPGA 数据通路。

> 前提：板卡已烧录 `pcie_dma.sof` 并**插入主机 PCIe 槽**（台面 JTAG 测不了 BAR，
> 只能看 `grn[1]` 心跳确认硬核在跑）。开机时 FPGA 需已配置完成，主机 BIOS 才能枚举
> 到端点（大 PCIe 设计有时需先烧录再冷启动主机）。

## Linux（推荐，能真正读写 BAR）

1. **确认枚举**：
   ```bash
   lspci -d 1234:1002 -v
   ```
   应看到设备，`Memory at ... 64-bit, prefetchable [size=256K]` 即 BAR0。
   记下 BDF（形如 `0000:01:00.0`）。

2. **读写 BAR0**（用 [pcimem](https://github.com/billfarrow/pcimem)，几十行的小工具）：
   ```bash
   B=/sys/bus/pci/devices/0000:01:00.0/resource0
   sudo ./pcimem $B 0x0   w              # 读偏移 0 的 32-bit
   sudo ./pcimem $B 0x0   w 0xDEADBEEF    # 写 0xDEADBEEF
   sudo ./pcimem $B 0x0   w              # 再读, 应回 0xDEADBEEF
   sudo ./pcimem $B 0x100 w 0x12345678    # 换个偏移
   sudo ./pcimem $B 0x100 w              # 应回 0x12345678
   ```
   写进去、读回来一致 → **PCIe 主机↔FPGA 片内 RAM 数据通路打通**。
   （地址范围 0x0..0x3FFFC，256KB；32-bit 对齐。）

3. **回环/吞吐脚本**（可选）：对整块 256KB 写伪随机、读回比对，统计带宽。
   PIO 单次访问慢（每次一个 TLP），吞吐验证请改用硬核 DMA 变体或项目 5。

## Windows（只能确认枚举）

- 设备管理器 → 查看含 `PCI\VEN_1234&DEV_1002` 的设备（可能在"其他设备"，无驱动
  正常）。或 PowerShell：
  ```powershell
  Get-PnpDevice | Where-Object InstanceId -match 'VEN_1234&DEV_1002'
  ```
  能看到 = PCIe 链路训练成功、配置空间可读（VID/DID/BAR 已被 BIOS 分配）。
- **BAR 读写**：Windows 无现成用户态 `mmap` 途径，需要写个 WDF/内核驱动把
  `resource0` 映射出来。要实测数据通路，**建议用 Linux**（第 2 步一条命令即可）。

## 排查

- `lspci` 看不到设备：多为 FPGA 未在主机上电前配好 → 先烧 .sof/.jic 再冷启动主机；
  或 x8 lane 未协商上（检查 `LnkSta` 里的 `Speed`/`Width`）。
- 能枚举但读全 `0xFFFFFFFF`：BAR 未分配或链路 down；`lspci -vv` 看 `LnkSta`。
- 读写不一致：确认偏移 32-bit 对齐、在 0..0x3FFFC 内。
