# mqnic 主机验证 —— ✅ 已在真实硬件上跑通（枚举 + 驱动 + 双网口 + DMA 队列）

**状态：✅ 2026-07-27 在 Ubuntu 主机（kernel 7.0.0，板卡在 PCIe 槽）完整验证通过。**
mqnic 内核驱动成功 probe，读通整颗 FPGA 的寄存器块树，建出 `/dev/mqnic0` + **两个网口**
`enp1s0np0/np1`，DMA 收发队列全部就绪、PTP 硬件时钟在跑。唯一没测的是"光口收发实际
数据包"——需要插 QSFP 模块/环回件（板上光笼当前空置，故 NO-CARRIER，属预期）。

- PCIe **VID 0x1234 / DID 0x1001**，class = **Ethernet controller [0200]**，Gen2 x8，
  BAR0 = 16MB（addr_width=24）。

## ✅ 验证结果

```
# lspci: 01:00.0 Ethernet controller [1234:1001], Gen2(5GT/s) x8
# 驱动 probe (dmesg):
mqnic 0000:01:00.0: IF features: 0x00001f11, Port count: 1
mqnic ...: TXQ count 1024 / RXQ count 256 / CQ 2048 / EQ 32, Max MTU 9214
mqnic ...: Registered device mqnic0
mqnic ... enp1s0np0: renamed from eth0
mqnic ... enp1s0np1: renamed from eth1     # IF_COUNT=2 -> 两个网口
mqnic ... enp1s0np0: mqnic_start_port on interface 0
mqnic ... enp1s0np1: mqnic_start_port on interface 1

# mqnic-dump -d /dev/mqnic0 (完整见 host/mqnic-dump.txt):
FPGA ID 0x432ac0dd, Board ID 0x198a0521, IF count 2
PHC time (ToD): 1785206218 s   period 6.206 ns     # ★ PTP 硬件时钟在跑 ★
Core clock freq: 124.768 MHz                        # 实测核心时钟(Gen2 coreclk)
CH0..3 clock freq: 390/331/390/336 MHz              # 4 条收发器 lane 时钟都活着(GXT 起来了)
RXQ 0..255: base 0x00000000ffdf4000... En=1 Len=1024 Prod=1024   # ★ DMA 收队列已装好+填满 ★
Statistics counters: Index0=8805 Index1=20147 ...   # FPGA 统计计数器经 DMA/BAR 读回, 非零

# ethtool -i enp1s0np0: driver mqnic, firmware-version 0.0.1.0, bus 0000:01:00.0
```

RXQ 的 base 是**驱动分配的主机 DMA 物理地址**、已写进 FPGA 队列寄存器并把 RX 环填满
(Prod=1024)——**证明 PCIe DMA 双向控制通路 + 收发描述符环全部就绪**。加上 PTP 时钟在走、
4 条 lane 时钟都活、统计计数器可读，mqnic 这颗 NIC 是真的活的。

## 复现步骤（Ubuntu）

### 1. 烧录（板卡在 PCIe 槽内，refclk 就绪）
```bash
quartus_pgm -c "Microsoft Catapult (64)" -m JTAG -o "P;output_files/qsfp_mqnic.sof"
```
让主机重新枚举：
```bash
echo 1 | sudo tee /sys/bus/pci/devices/0000:01:00.0/remove
echo 1 | sudo tee /sys/bus/pci/rescan
```
> mqnic 的 16MB BAR 落在桥的**非可预取** 32-bit 内存窗口(0x84000000-0x85ffffff)，
> 不像项目3 那样受 remove+rescan 破坏可预取窗口的影响；但若读 BAR 全 0xffffffff，
> 参见 [../3_PCIE_DMA/HOST_VALIDATION.md](../3_PCIE_DMA/HOST_VALIDATION.md) 的桥窗口修复。

### 2. 装工具链 + 编译驱动（见 `driver_mqnic_kernel7/` 的 kernel 7.0 移植补丁）
```bash
sudo apt-get update && sudo apt-get install -y build-essential   # 主机原本没有 gcc/make
cd corundum/modules/mqnic && make        # 生成 mqnic.ko
```
> ⚠️ 本 fork 的驱动只带到 kernel 5.15 的兼容 guard，**在 kernel 6.16/7.0 上要打 5 处补丁**
> (见下)。补丁后的源文件存在 `driver_mqnic_kernel7/`。

### 3. 加载 + 验证
```bash
for m in ptp i2c-algo-bit i2c-mux i2c-dev; do sudo modprobe $m; done
sudo insmod mqnic.ko
dmesg | grep mqnic | tail -40          # 看 probe + 建网口
ip -br link | grep enp1s0              # enp1s0np0 / enp1s0np1
sudo ethtool -i enp1s0np0
cd ../../utils && make mqnic-dump && sudo ./mqnic-dump -d /dev/mqnic0   # 板卡/固件/队列信息
```

### 4. 真正跑网络包（需要硬件）
光笼插 QSFP28 模块或环回件后：`sudo ip addr add ... ; sudo ip link set enp1s0np0 up`，
对端 ping。当前板上光口空置 → NO-CARRIER，属正常。

## 🔧 kernel 6.16 / 7.0 驱动移植补丁（本 fork 原本只到 5.15）

| 文件 | 改动 | 内核变更 |
|------|------|----------|
| `mqnic_main.c` | `platform_driver.remove` 回调改返回 `void`（版本 guard） | 6.11 起 `.remove` 返回 void |
| `mqnic_dev.c` | `strlcpy` → `strscpy`（3 处） | 6.8 移除 `strlcpy` |
| `mqnic.h` | 加兼容宏：`del_timer_sync`→`timer_delete_sync`、`from_timer`→`timer_container_of` | 6.16 改名旧 timer API |
| `mqnic_board.c` | 加 `#include <linux/hex.h>`（>=5.18 guard） | `mac_pton()` 从 kernel.h 移到 hex.h |
| `mqnic_ethtool.c` | `get_rxfh/set_rxfh` 改用 `ethtool_rxfh_param`；`get_ts_info` 改 `kernel_ethtool_ts_info`（均加版本 guard） | 6.8 改 rxfh 签名，6.11 改 ts_info |

补丁后的源文件放在 `driver_mqnic_kernel7/`（可直接覆盖到 `corundum/modules/mqnic/`），
`utils/` 另需把 Windows 检出丢失的软链恢复：`utils/lib`→`../lib`、`utils/include`→
`../include`、`lib/mqnic/mqnic_hw.h`/`mqnic_ioctl.h`→`../../modules/mqnic/*`。
