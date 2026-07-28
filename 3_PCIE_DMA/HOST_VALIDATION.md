# 3 PCIE_DMA 主机侧验证 —— ✅ 已在真实硬件上跑通

设计：PCIe **Gen2 x8** 端点，**BAR0 = 256KB 片内 RAM**，VID `0x1234` / DID `0x1002`。
主机把 BAR0 映射进地址空间后直接 32-bit 读写，即验证 PCIe↔FPGA 数据通路。

**架构（自包含 TLP 目标，不依赖 qsys 互连）**：
`altera_pcie_s10_hip_ast`（Avalon-ST 原始 TLP）→ Corundum `pcie_s10_if`（AST↔TLP 桥）
→ `pcie_axil_master_minimal`（BAR TLP→AXI-Lite 主）→ `axil_ram`（256KB 片内）。
`rtl/pcie_dma.v` 手连，复位学项目5：`reset_release`→ninit_done，`iopll_100mhz`(usr_refclk0)
→clk_100mhz，`sync_reset`→rst_100mhz，`npor=!rst_100mhz`。

## ✅ 验证结果（2026-07-27，主机 192.168.68.61，板卡在 PCIe 槽）

```
+0x0  <- 0xdeadbeef ; 读回 0xdeadbeef   ✓
+0x40 <- 0xcafef00d ; 读回 0xcafef00d   ✓
full-256KB unique-pattern: PASS (65536 words)   # 每个 32-bit 字唯一值, 无地址混叠
byte-enable (0x100): 0xffff1234                  # 16-bit 部分写只改低 2 字节, 字节使能全通
boundary 0x00000/0x00004/0x3fff8/0x3fffc: PASS   # 完整 18-bit BAR 地址范围译码正常
```

主机↔FPGA 片内 RAM 数据通路 **完全打通**（host mmap → MemWr/MemRd TLP → S10 硬核
→ Corundum TLP 栈 → axil_ram）。

## Linux 复现步骤

1. **烧录**（板卡在槽内，refclk 就绪才能配 SRAM；台面 JTAG 因无 refclk 会失败）：
   ```bash
   quartus_pgm -c "Microsoft Catapult (64)" -m JTAG -o "P;output_files/pcie_dma.sof"
   ```
   改了 BAR 大小/类型需让主机重新枚举：
   ```bash
   echo 1 | sudo tee /sys/bus/pci/devices/0000:01:00.0/remove
   echo 1 | sudo tee /sys/bus/pci/rescan
   ```

2. **⚠️ 关键：修复上游桥可预取窗口**（见下"根因"）。`remove+rescan` 后必跑：
   ```bash
   sudo bash host/pcie_fix_bridge_window.sh
   ```

3. **确认枚举 + 读写 BAR0**：
   ```bash
   lspci -d 1234:1002 -v      # 应见 Memory at 40_xxxxxxxx (64-bit, prefetchable) [size=256K]
   BDF=$(lspci -d 1234:1002 | cut -d' ' -f1)
   sudo python3 host/bar_mem.py 0000:$BDF 0x0 0xDEADBEEF   # 写
   sudo python3 host/bar_mem.py 0000:$BDF 0x0              # 读回 0xdeadbeef
   ```
   地址范围 `0x0..0x3FFFC`（256KB，32-bit 对齐）。

## 🔴 根因记录：读全 0xffffffff 其实是主机侧桥窗口问题，**不是 FPGA 的锅**

调了很久 BAR 读全 `0xffffffff`、写不进——**avmm 和 hip_ast 两套完全不同的逻辑症状一模一样**，
这本身就说明问题在"共因"而非应用逻辑。决定性证据：一次 MemRd 之后，设备和上游根口的
**所有 AER 位全清**（无 `UnsupReq`、无 `CmpltTO` 完成超时、无 abort）——快速 `0xffffffff`
且零错误 = 内存 TLP **根本没被转发到 FPGA**，死在地址路由。

查上游桥 `00:01.0` 的可预取窗口寄存器：
- `PREF_BASE/LIMIT (0x24) = 0x0001fff1` → base=`0xfff00000` > limit=`0x000fffff`（**base>limit=窗口禁用**）
- `PREF_*_UPPER32 (0x28/0x2c) = 0` → 够不到 BAR 的 `0x40` 高位

而设备 BAR 在 `0x40_17100000`（BAR0=`1710000c` 可预取64位, BAR1=`00000040`）。
`remove+rescan` 把桥的可预取窗口留成了"禁用+upper32=0"，于是发往 BAR 的内存 TLP
全部无法转发。**FPGA 设计从头到尾是对的。**

**修复**（`host/pcie_fix_bridge_window.sh` 做的事）：把桥窗口重设为覆盖 BAR：
```bash
sudo setpci -s 00:01.0 0x28.l=0x00000040   # PREF_BASE_UPPER32 = 0x40
sudo setpci -s 00:01.0 0x2c.l=0x00000040   # PREF_LIMIT_UPPER32 = 0x40
sudo setpci -s 00:01.0 0x24.l=0x17111711   # base/limit[31:20]=0x171, 均置 64-bit-cap 位
sudo setpci -s 00:01.0 COMMAND=0x0006       # 桥 Mem 转发
sudo setpci -s $BDF    COMMAND=0x0006       # 设备 Mem+BusMaster
```
> 冷启动（不做 remove/rescan）时 BIOS 会正常建好该窗口；本问题仅由热插拔式的
> `remove+rescan` 触发。改了 bitstream 后若能冷重启主机，可绕过此坑。

## 排查速查

- 能枚举但读全 `0xFFFFFFFF` 且 `lspci -vv` 无任何 AER 错误 → 十有八九是上游桥窗口没覆盖 BAR，
  跑 `host/pcie_fix_bridge_window.sh`。
- `lspci` 看不到设备：FPGA 未在主机上电前配好 → 先烧 .sof 再冷启动主机；或 x8 未协商上（看 `LnkSta`）。
- 读写不一致：确认偏移 32-bit 对齐、在 `0..0x3FFFC` 内。
