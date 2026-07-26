# 实验 2 (3.2): DDR4 EMIF — 电脑直接读写板卡内存

> 在实验 1 基础上加入 EMIF DDR4 (RDIMM 1Rx8)、板级 I2C (SPD 读取)
> 与校准调试通道。固件同时保留全部 LED 控制功能。

## ★ 双通道 (2026-07-26, 硬件验证通过) ★

**DIMM0 + DIMM1 双通道**已跑通:两条 8GB 1Rx8 都校准成功、电脑读写各 16/16 字通过。

- **A-2020 有 4 个独立 DDR4 通道**(各是 FPGA 独立 EMIF):
  DIMM0=CH0=`ddr4_mem[2]`(CK AP10)、**DIMM1=CH1=`ddr4_mem[3]`(CK L6, refclk K8)**、
  DIMM2=CH2、DIMM3=CH3。DIMM0/1 是版图"3"区 Lower/Upper 一对。
- **组双通道**:DIMM0 现有那条 + **DIMM1** 插一条同规格 1Rx8。
- 工程:`make_qsys.tcl` 里 `foreach emif {emif0 emif1}` 双 EMIF;CH1 数据映射
  到 `0x4_0000_0000`(8GB);`gen_ddr_pins.py <PINDEF> 0,1` 生成两通道引脚。
- **坑**:两个 EMIF 同 I/O 列只能有一个 cal_debug 调试工具包 → CH1 关 cal_debug
  (校准成功/失败仍由 status 上报);qsys-script 会把组件转 generic 且加 `_0` 后缀,
  qsf 需用 `QSYS_FILE + IP_FILE ip/jtag_sys/*.ip`(不是 QIP)、去掉 `_0`、
  emif1.ip 剥掉 cal_debug 端口。详见顶层 memory / 提交记录。
- 验证:`python dual_ch_test.py`(读两通道校准 + 各写16字读回比对)。

电脑经板载 USB-Blaster (FT232H) → JTAG → **ISSP (In-System Sources &
Probes)** 通道读写 FPGA，用原生 GUI 程序点按钮切换 LED 灯效。

```
电脑GUI(点按钮) ──USB──► FT232H ──JTAG──► ISSP 源/探针 ──► LED灯效引擎
```

> **重要经验（实测得出）**：本板卡的 Catapult 定制 JTAG 驱动
> (`jtag_hw_microsoft_catapult.dll`) 只支持烧录和简单移位，**不支持
> System Console 的 JTAG-Avalon 流式传输**——任何 `master_read/write`
> 都会永久挂死（用纯 Intel 官方组件"JTAG桥→片内RAM"对照通路验证过，
> 同样挂死，与自写 RTL 无关）。因此上位机通道改用单次移位的 ISSP。
> 工程里仍保留 JTAG-Avalon 桥和寄存器组代码，供换用标准 USB-Blaster II
> 时使用。

## 使用步骤

1. **烧录**：Programmer 下载 `led_ctrl.sof`（或烧 `led_ctrl.jic` 固化）。
   板载 USB-Blaster 驱动配置见资料包 `Onboard_jtag/readme.txt`
   （`jtag_hw_microsoft_catapult.dll` 需复制到 `H:\fpga\quartus\bin64`）。
2. **启动控制程序**，两种任选：

   **方式 A（推荐）— 独立 GUI 程序**（需要本机 Python 3，界面为原生窗口，
   自动在后台启动隐藏的 system-console 作为 JTAG 通道）：
   ```
   python H:\led_ctrl\led_gui.py
   ```
   功能：模式按钮 / 速度档 / 手动勾选直控 / 板卡 LED 实时状态镜像
   （每 0.5s 回读一次，界面上的圆点和板上灯同步亮灭）。
   Quartus 不在默认路径时设置环境变量 `SYSCON_PATH` 指向
   `system-console.exe`。

   **方式 B — System Console Dashboard**（`--desktop_script` 带 GUI 启动；
   `--script` 是无界面批处理模式，Dashboard 显示不出来）：
   ```
   H:\fpga\syscon\bin\system-console --desktop_script=H:\led_ctrl\led_panel.tcl
   ```
   若启动时板卡未就绪，烧录后在 Tcl 控制台输入 `led::connect` 重连。
3. 弹出的 "MSA-2020 LED 控制台" 面板上点按钮即可：
   - **LED Pattern**：自动轮换 / 计数器闪烁 / 流水灯 / 呼吸灯 / 波浪呼吸 / 全灭
   - **速度档位**：x1 ~ x32
   - **手动直控**：勾选任意 LED 组合后点"应用"
   - **读取状态**：回读板卡当前模式与 LED 实时电平

   Dashboard 不可用时可直接敲命令：`led::mode 2`、`led::manual 0x155`、
   `led::speed 3`、`led::status`。

## ISSP 通道位定义（上位机实际使用）

- **source[15:0]**（电脑 → FPGA）：`[2:0]` 模式（0=自动轮换 1=闪烁 2=流水
  3=呼吸 4=波浪 5=手动）| `[11:3]` 手动 LED 电平 | `[14:12]` 速度档 0~5 |
  `[15]` 置 1 = 上位机接管（清 0 交还板卡默认逻辑）
- **probe[31:0]**（FPGA → 电脑）：`[8:0]` LED 实时电平 | `[11:9]` 当前生效
  灯效 | `[14:12]` 模式 | `[15]` 接管状态 | `[19:16]` 心跳 |
  `[31:24]` 签名 0x5A（上位机据此确认板内是 led_ctrl）

## Avalon 寄存器映射（备用，标准 USB-Blaster II 时可用）

| 地址 | 名称 | 读写 | 说明 |
|------|------|------|------|
| 0x00 | ID     | RO | 恒为 0xA2020001，上位机识别用 |
| 0x04 | CTRL   | RW | [2:0] 0=自动轮换 1=闪烁 2=流水 3=呼吸 4=波浪 5=手动 |
| 0x08 | MANUAL | RW | [8:0] 手动模式下 LED 电平 |
| 0x0C | SPEED  | RW | [2:0] 速度档 0~5，每档速度 ×2 |
| 0x10 | STATUS | RO | [2:0]模式回读 [6:4]当前生效灯效 [24:16]LED实时值 |
| 0x14 | PHASE  | RO | 相位计数器实时值（读数在变=板卡活着） |

注：ISSP 接管期间（source[15]=1），Avalon 寄存器的模式/手动/速度设置被
ISSP 值覆盖。

## 文件说明

- `led_ctrl.v` — 顶层（JTAG 桥 + 核心）
- `led_ctrl_core.v` — 寄存器组 + 灯效引擎（Avalon-MM 从机）
- `jtag_sys.qsys` — Platform Designer 系统（仅含 JTAG-Avalon 桥），由 `make_qsys.tcl` 生成
- `led_gui.py` — **电脑端独立 GUI 程序**（Python tkinter，推荐）
- `led_panel.tcl` — 电脑端控制面板（System Console Dashboard 方式）
- `tb_led_ctrl_core.v` — 核心逻辑仿真测试台
- `led_ctrl.qsf / .sdc / .qpf` — 工程与约束（VID 供电参数照搬 blink，勿改）

## 内存读写通道（DDR4 的前置框架，已上板验证）

第二个 ISSP 实例（instance_id=MEM，source 96bit / probe 64bit）+
`issp_mem_bridge.v` 命令 FSM 构成通用内存访问通道：

```
GUI内存页 ─ISSP(MEM)─► issp_mem_bridge FSM ─Avalon 32bit─► mm_bridge ─► 片内RAM 64KB
                                                            (DDR4 就绪后此处改接 EMIF)
```

- source: `[31:0]` 写数据 | `[61:32]` 字地址 | `[62]` 1=写 0=读 |
  `[71:64]` 命令序号（变化即触发，回读探针中序号一致=完成）
- probe: `[31:0]` 读数据 | `[39:32]` 完成序号 | `[43:40]` 心跳 |
  `[63:56]` 签名 0xA5
- 实测约 150+ 次读写/秒（JTAG 调试速度，peek/poke 足够；大流量走 PCIe）

### 板卡 DDR4 硬约束（从 PINDEF 布线得出，选内存条必看）

每通道仅布线 **9 对 DQS + 9 根 DBI_n、1 根 cs_n**（DQ 72 根含 ECC 齐全）：

- **只支持 x8 颗粒、单 rank 的 DIMM（标签 "1Rx8"）**
- x4 颗粒条（服务器常见 2Rx4/1Rx4 RDIMM）缺 9 对 DQS 布线，物理无法工作
- 双 rank 条缺第二片选，不可用
- UDIMM/RDIMM、ECC/非 ECC 均可；速率 ≥2133（板卡上限 2400MT/s）
- 槽位映射：丝印 DIMM0/1/2/3 ↔ 信号 ddr4_mem[2]/[3]/[0]/[1]，
  各通道 132 条引脚约束（含 RZQ、150MHz 参考时钟）见 PINDEF ASSIGNMENTS

## DDR4 内存读写（已打通 ✓）

**电脑可直接读写板上 8GB DDR4 RDIMM**（GUI 内存页 / `SysCon.mem_read/mem_write`），
单通道（丝印 DIMM0），校准通过、跨 4GB 地址范围读写验证 14/14、数据保持正常，
约 150+ 次操作/秒。

**校准失败的两个根因与修法**（调试历程的结论，换板/扩通道必看）：
1. **RDIMM 的 PAR/ALERT_n 必须连接**：`MEM_DDR4_ALERT_PAR_EN=true`，
   alert_n 放置 `AC_LANES` lane0/pin10（par 固定在 lane0/pin11，与之相邻；
   从 EMIF 生成的 readme 引脚表可推导）。PAR 悬空时 RCD 收不到有效
   parity，四通道一致性立即失败。
2. **时序参数让 IP 自动推导**：删除手工设置的 TCL/WTCL 后 IP 推导出
   TCL=18/WTCL=12（手工锁的 CWL16 差 4 拍导致训练失败）。

**地址映射**（经 ISSP 内存桥，34 位字地址）：
| 基址 | 设备 |
|------|------|
| 0x0_0000_0000 | DDR4 8GB（FSM 可达前 4GB） |
| 0x2_0000_0000 | I2C 主机 CSR（板级总线 AC28/AB28，可读 DIMM SPD，见 spd_read.py） |
| 0x2_8000_0000 | EMIF cal_debug（校准调试窗口） |

**SPD 实测**（HMA81GR7CJR8N-XN @ I2C 0x50）：DDR4/RDIMM/1Rx8/72bit 确认，
RCD 厂商 0xB380（IDT/Renesas），校准用 EMIF 默认 RCD 参数即通过。

**扩展多通道**：I/O 列3=DIMM0+DIMM1、列2=DIMM2+DIMM3；每列只允许一个
cal_debug 调试接口；ba/bg 引脚修正表见 gen_ddr_pins.py FIXUPS（四槽齐全）。

## 二次开发

以后想让电脑读板内其他数据（EMIF 校准状态、错误计数器等）：在
`make_qsys.tcl` 里加宽 probe 位宽（最大 511 bit）或增加新的 ISSP 实例
（用不同 instance_id 区分），把信号接进 `led_ctrl_core.v`，电脑端
`issp_read_probe_data` 直接读。Signal Tap 逻辑分析仪与本板卡驱动的
兼容性未验证，如需波形调试建议先小规模试用。
