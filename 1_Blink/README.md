# 实验 1: LED 控制 — 电脑端按钮控制 LED Pattern

> MSA-2020 (A-2020) 板卡入门实验。在官方 blink 示例基础上加入
> ISSP 上位机通道, 电脑 GUI 点按钮切换 LED 灯效。

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

## 二次开发

以后想让电脑读板内其他数据（EMIF 校准状态、错误计数器等）：在
`make_qsys.tcl` 里加宽 probe 位宽（最大 511 bit）或增加新的 ISSP 实例
（用不同 instance_id 区分），把信号接进 `led_ctrl_core.v`，电脑端
`issp_read_probe_data` 直接读。Signal Tap 逻辑分析仪与本板卡驱动的
兼容性未验证，如需波形调试建议先小规模试用。
