# MSA-2020 (Microsoft A-2020) FPGA 板卡实验集

面向退役数据中心 FPGA 板卡 **MSA-2020**（Microsoft Catapult A-2020，
Stratix 10 `1SG280LN2F43E2VG`）的开源实验工程与上位机工具。

## 项目列表

| # | 项目 | 内容 | 状态 |
|---|------|------|------|
| **1** | [Blink](1_Blink/) | LED 灯效引擎 + ISSP 上位机通道 + 电脑 GUI 点按钮控制/实时回显 | ✅ **烧录即用**，板侧 LED 计数器规律闪烁 |
| **2** | [EMIF](2_EMIF/) | DDR4 内存：EMIF 校准 + 电脑直接读写 8GB RDIMM，**双通道**(DIMM0+DIMM1) | ✅ **硬件验证**：双通道均校准成功、读写各 16/16 字通过 |
| **3** | [PCIE_DMA](3_PCIE_DMA/) | 独立 PCIe 最小实验：主机经 BAR0 直接读写 FPGA 256KB 片内 RAM（Gen3x8 Avalon-MM） | 🧩 **设计完成**（qsys+顶层+约束齐全）；叶子 IP HDL 需 Platform Designer GUI 生成后编译 |
| **4** | [100GBase_loop](4_100GBase_loop/) | QSFP0 收发器点亮 + retimer + 100G MAC，环回验证 | ✅ 收发器 4×25.78G 环回 / retimer 均**硬件验证**；⛔ bonded 100G MAC 板级受限 |
| **5** | [Corundum_fork_on_MSA2020](5_Corundum_fork_on_MSA2020/) | Corundum mqnic NIC 移植（PCIe DMA + 100G） | 🚧 **已编译出 .sof**；驱动仅 Linux；待主机 PCIe 槽验证 |

每个项目目录自成一体（Quartus 工程 + RTL + 上位机脚本 + README）。用
Quartus Prime Pro 23.3 打开各自的 `.qpf` 编译，或直接烧录自带的 `.sof`。
（4 是多个子工程合集，见其目录内 README。）

## 板卡关键知识（各实验共用，踩坑实录）

- **JTAG 限制**：板载 FT232H 用 Catapult 定制驱动
  （`jtag_hw_microsoft_catapult.dll`），只支持烧录和简单移位；
  System Console 的 JTAG-Avalon streaming 会**永久挂死**。
  所有上位机通信因此走 **ISSP**（单次移位），实测稳定 ~150 操作/秒。
- **VID 供电配置**（`PWRMGT_*`、SDM 引脚）**必须**与官方 blink 示例一致，
  配错可能烧毁板卡——各 qsf 均已包含，勿改。
- **DDR4**：**4 个独立通道**，DIMM0/1/2/3 ↔ `ddr4_mem[2]/[3]/[0]/[1]`
  （CK 脚 AP10/L6/AU22/K31）；每通道只布线 9 组 DQS + 1 片选 →
  **只支持 1Rx8**（x8 颗粒、单 rank），上限 2400MT/s。双通道见 2_EMIF README。
- **DDR4 校准根因**（详见 2_EMIF README）：RDIMM 的 PAR/ALERT_n 必须连接；
  时序参数（TCL/WTCL）让 EMIF IP 自动推导、勿手工锁定。
- 板级共享 I2C：`SCL=AC28 / SDA=AB28`（3.0-V LVTTL），挂有 DIMM SPD (0x50)、
  FPC202、DS250DF810 retimer 等。
- **QSFP0 收发器**（25.78G GXT）：refclk `AD34`（644.53125MHz），
  TX/RX 接**非连续物理通道 0,1,3,4**（为 4×25G 独立 lane 设计，非 bonded 100G）；
  正解拓扑 = Corundum 520N_MX（master ATX + atx_blw 缓冲 + iqclk refclk），
  `anlg_link=sr`。详见 4 / 5 内 README。
- 100MHz 用户时钟 `PIN_AD6`（1.8V）；同款板参考
  [SuperSodaSea/Plugcat](https://github.com/SuperSodaSea/Plugcat)。
- **PCIe**：Gen3 x16，`TX BB34..` / `RX AV30..` / refclk `AM34` / perst `AC26`。

## 上位机环境

Windows + Python 3 + Quartus Prime Pro 23.3（syscon 作 JTAG 后端）。
首次使用需按板卡资料包安装 FTDI D2XX 驱动并把定制 dll 复制到 `quartus\bin64`。
（注：5 Corundum mqnic 的**网卡驱动仅 Linux**，Windows 只能验证 PCIe 枚举，
见 `5_Corundum_fork_on_MSA2020/HOST_VALIDATION.md`。）

## 路线图

- [x] 1 LED 控制 + 上位机 GUI
- [x] 2 DDR4 EMIF 单通道 + **双通道**（DIMM0+DIMM1，硬件验证）
- [x] 4 QSFP0 4×25.78G 收发器环回（硬件验证）+ retimer（硬件验证）
- [x] 5 Corundum mqnic 移植编译出 .sof
- [ ] 2 DDR4 四通道扩展（DIMM2/DIMM3，同法可扩）
- [x] 3 独立 PCIe 最小实验设计完成（Gen3x8 Avalon-MM，BAR0→256KB 片内 RAM）；待 GUI 生成叶子 IP 后编译
- [ ] 4 bonded 100G MAC（板级受限，探索中）
- [ ] 5 mqnic 主机 PCIe 槽 + Linux 驱动验证
