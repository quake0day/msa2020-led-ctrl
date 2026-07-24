# MSA-2020 (Microsoft A-2020) FPGA 板卡实验集

面向退役数据中心 FPGA 板卡 **MSA-2020**（Microsoft Catapult A-2020，
Stratix 10 `1SG280LN2F43E2VG`）的开源实验工程与上位机工具。
所有实验均已在真板验证。

## 实验目录

| 实验 | 内容 | 状态 |
|------|------|------|
| [01_led_control](01_led_control/) | LED 灯效控制：FPGA 灯效引擎 + ISSP 上位机通道 + 电脑 GUI 点按钮控制/实时回显 | ✅ 已验证 |
| [02_ddr4_emif](02_ddr4_emif/) | DDR4 内存：EMIF 校准通过，电脑直接读写 8GB RDIMM；含板级 I2C 读 SPD、校准调试通道 | ✅ 已验证 |

每个实验目录自成一体（Quartus 工程 + RTL + 上位机脚本 + README），
用 Quartus Prime Pro 23.3 打开各自的 `led_ctrl.qpf` 编译，或直接烧录
自带的 `led_ctrl.sof`。

## 板卡关键知识（两实验共用，踩坑实录）

- **JTAG 限制**：板载 FT232H 用 Catapult 定制驱动
  （`jtag_hw_microsoft_catapult.dll`），只支持烧录和简单移位；
  System Console 的 JTAG-Avalon streaming 会**永久挂死**。
  所有上位机通信因此走 **ISSP**（单次移位），实测稳定 ~150 操作/秒。
- **VID 供电配置**（`PWRMGT_*`、SDM 引脚）**必须**与官方 blink 示例一致，
  配错可能烧毁板卡——两个实验的 qsf 均已包含，勿改。
- **DDR4 硬约束**：每通道只布线 9 组 DQS + 1 根片选 →
  **只支持 1Rx8（x8 颗粒、单 rank）的 DIMM**；UDIMM/RDIMM、ECC 与否均可，
  速率上限 2400MT/s（150MHz 参考时钟）。
- **DDR4 校准两大根因**（详见实验 2 README）：RDIMM 的 PAR/ALERT_n
  必须连接；时序参数（TCL/WTCL）让 EMIF IP 自动推导、勿手工锁定。
- 板级共享 I2C：`SCL=AC28 / SDA=AB28`（3.0-V LVTTL），挂有 DIMM SPD
  (0x50)、FPC202、DS250DF810 retimer 等。
- 100MHz 用户时钟 `PIN_AD6`（1.8V）；QSFP 收发器配置可参考同款板的
  [SuperSodaSea/Plugcat](https://github.com/SuperSodaSea/Plugcat)。

## 上位机环境

Windows + Python 3 + Quartus Prime Pro 23.3（syscon 作为 JTAG 后端，
GUI 自动隐藏调用）。首次使用需按板卡资料包 `Onboard_jtag/readme.txt`
安装 FTDI D2XX 驱动并把定制 dll 复制到 `quartus\bin64`。

## 路线图

- [x] LED 控制 + 上位机 GUI
- [x] DDR4 EMIF 单通道（8GB RDIMM 读写）
- [ ] DDR4 多通道扩展（引脚修正表已备齐）
- [ ] QSFP/100G（Corundum 方向，transceiver 资料已就绪）
