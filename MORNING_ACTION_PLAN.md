# Corundum/QSFP 方向 — 明早行动计划

> 状态截止 2026-07-24 凌晨。原则:先不烧录已在夜里全部执行;能独立编译的已编译好。

## 一句话总结（已更新：阶段1、2 均已硬件验证通过）

| 阶段 | 目标 | 状态 |
|---|---|---|
| **阶段2 Retimer/I2C** | DS250DF810+FPC202 初始化 | ✅ **编译+烧录+硬件验证通过**(DS250/FPC202 I2C 初始化完成) |
| **阶段1 收发器点亮** | QSFP0 4×25.78G PRBS | ✅ **编译+烧录+硬件验证通过**(ATX PLL 锁定、4×25.78G PRBS31 内部环回全部锁定零误码) |
| **阶段3 100G MAC** | alt_e100s10 MAC+PCS | 🔧 收发器物理层已解决;需接 e100 MAC 或用 Corundum 25G×4→100G |
| **阶段4 Corundum** | PCIe DMA + mqnic | 🔧 收发器基础已就绪(06_qsfp_xcvr 移植自 520N_MX);待接 PCIe+mqnic |

> **阶段1 的突破**: GXT 布局墙的解法 = Corundum 520N_MX 拓扑(master ATX + atx_blw 缓冲 +
> 4 独立单通道 PHY + iqclk refclk)+ **anlg_link=sr**(本板专属)+ **master/buffer 时钟按
> 物理三联组分配**(下三联组=data[0],[3] / 上三联组=data[1],[2])。工程 `06_qsfp_xcvr`。
> 验证: `python 06_qsfp_xcvr/xcvr_test.py` → 读各通道误码累加冻结=链路干净。

---

## ✅ 阶段2 — 可立即烧录

- 工程:`H:\led_ctrl\04_qsfp_retimer\`
- 比特流:`output_files\retimer_init.sof`(0 error,timing slack +6.183ns)
- 烧录后验证:
  ```
  cd H:\led_ctrl\04_qsfp_retimer
  python retimer_test.py
  ```
  读 ISSP(instance RTMR,签名 0x52),报 `ds_ready` / `fpc_ready` / QSFP 模块在位。
- 本地 LED:LED0=系统运行,LED1=DS250 完成,LED2=FPC202 完成,LED3=init_ready。
- ⚠️ 现用的是 Plugcat **基础使能**序列(FC/FF/RST_REGS/1E)。做 25.78G **外部环回**
  时还要给 DS250 补速率/自适应寄存器(0x2F 掩码 0x70=25.78G、0x31=0x40 adapt Mode2、
  0x3D/3E/3F FIR)。这些在 `sources\DS250DF810.v` 的 `DATA()` 函数里加即可。

---

## ⛔ 阶段1 / 阶段3 — 根因已彻底定位到最后一层

**今夜把问题从"完全布不通"一路推进到"仅剩 1 个 LC_PLL_MUX 待 refclk 分发"。**
关键突破链(每条都编译验证过):

1. **PLL 类型:MAC 要 ATX 不是 fPLL。** fPLL 能清掉 LC_PLL_MUX 报错但通道退化成
   GX 型,与 GXT 引脚冲突;ATX 才有正确 GXT typing。
2. **两个 ATX 必须级联(master/slave),不是两个独立 ATX。** 这是之前
   LC_PLL_MUX 布不通的主因。改级联后,不可布局组件从 **4 个降到 1 个**。
   - 参考:Intel 官方模板 `H:\fpga\ip\altera\ethernet\alt_e100s10\
     example_project\templates\compilation_rtl_template.v.terp`
   - 已按此生成 `ip\macatx_m.ip`(master)+`ip\macatx_s.ip`(slave),级联线
     `gxt_output_to_*_atx → gxt_input_from_*_atx`,顶层已接好。
3. **级联方向无关**(两个方向都试了,报错只在 master/slave 间换)。
4. **最后一堵墙 = 单 refclk 到双三联组。** CAUI-4 的 4 通道横跨 bank 1F 的
   两个物理三联组(TX CGB 在 y=91 和 y=111),各需一个 ATX。两个 ATX 都从
   唯一的 refclk 引脚 **AD34** 取参考时钟,导致两个 LC_PLL_MUX 都被钉在 AD34
   的 region ≤93,够不到 y=111 的上三联组 → slave/master 之一无法布局。
   - **PINDEF 已确认:QSFP0 的 644.53M 只走 AD34 一个引脚**(qsfp1 走 H34),
     没有第二个 refclk 脚,所以不能像 Intel dev board 那样用两个 refclk 引脚。

### 重大更新:找到已发布的可编译参考 —— Corundum 520N_MX

深夜克隆了 Corundum(`H:\led_ctrl\05_corundum\corundum`),其
`fpga/mqnic/520N_MX/fpga_25g` 是**已发布、可编译的 Stratix 10 4×25.78G GXT
设计**(同族 H-tile),已解单-refclk 多通道 GXT 布局。正解拓扑:
- **master ATX**:`enable_GXT_clock_source=atx_lcl`,本地生成时钟向上输出
- **slave 是时钟缓冲不是独立 PLL**:`enable_GXT_clock_source=atx_blw`,从下方
  master 取时钟(我之前 slave 当独立 PLL 才布不下)
- **4 个独立单通道 Native PHY**(非一个 4 通道 PHY,也非 e100 bonded MAC),
  CDR refclk 走 **IQ 网络**(`set_cdr_refclk_receiver_detect_src=iqclk`)

**关键教训:e100 MAC(bonded CAUI-4)内部自己布 4 通道,外挂 ATX 无法对齐它的
内部 CGB —— 我给 e100 硬套 Corundum 的 PLL 参数,master/slave 轮流布不下,证明
两种布局模型不兼容。** 所以:
- **阶段1(4×25.78G PRBS)+ 阶段4(Corundum)**:走 Corundum 独立单通道 PHY 拓扑
  (已验证可编译),**不用 e100 MAC**。直接以 520N_MX 为基板移植到 A-2020。
- **阶段3(100G bonded MAC)**:必须用 e100 自己的 Generate Example Design 做
  MAC+ATX 协同布局(GUI)。

### 明早两条解法(需连板/GUI)

**解法 A(推荐,最稳):Generate Example Design 自动算 refclk 分发**
1. Quartus GUI 打开 `H:\led_ctrl\03_qsfp_100g\ip\e100.ip` → 进 Parameter Editor。
2. 右上 **"Generate Example Design…"** → 输出到 `03_qsfp_100g\mac_ed\`。
3. 先原样编译确认过 fitter(证明 Intel 布局 OK),再把 QSFP0 引脚换成本板(见下)
   、refclk 接 AD34,重编得 `.sof`。这一步会自动处理 refclk 网络分发。

**解法 B(纯改约束,若想省 GUI):配 S10 参考时钟网络**
- 让上三联组的 ATX 从"参考时钟网络"取 AD34 的时钟(而非专用引脚)。
- 在 `ip\macatx_s.ip` 的 ATX 里找 reference clock source / refclk network 选项,
  或给 slave ATX 加 refclk 网络约束。跨度能否覆盖 y=91→y=111 需连板 fitter 验证。
- 这条不确定性高,建议先试解法 A。

> 阶段1(收发器点亮 PRBS)与阶段3(100G MAC)是**同一堵 refclk 墙**;解法 A 一步
> 同时解决两者(MAC 内部含收发器)。单独的手搭 Native PHY PRBS(`03_qsfp_prbs`)
> 因 GXT example design 不支持,不建议再走。

### 本板 QSFP0 引脚(Plugcat 验证,替换 example 里的引脚时用)

```
refclk 644.53125MHz HCSL : AD34 / AD33(n)     Bank 1F
TX (lane 0/4/3/1)        : AG40 AC40 AD42 AF42
RX                       : AG36 AC36 AB38 AD38
I2C(retimer)            : SCL=AC28 SDA=AB28   3.0-V LVTTL
```
⚠️ **禁止改动** qsf 里的 PWRMGT_* / USE_*_SDM_IO 电源/VID 配置(改了可能烧板)。

---

## 阶段4 — Corundum(待 1/3 通后)

- 需要板卡插进主机 PCIe 槽 + Corundum 的 mqnic 驱动。
- 依赖阶段3 的 100G MAC 通道。等 MAC example 能编译出 .sof 后,
  用 Corundum 的 `fpga/mqnic/` 模板替换其 CMAC/MAC 接口即可。

---

## 今夜产物清单

- ✅ `04_qsfp_retimer\output_files\retimer_init.sof` — 可烧录
- ✅ `04_qsfp_retimer\retimer_test.py` — PC 端验证
- 🔧 `03_qsfp_100g\` — MAC 工程,ATX 级联 master/slave 已接好,不可布局组件
  从 4→1,仅剩单-refclk 到双三联组的 refclk 分发(解法 A/B)。PLL类型/连接/参数全对
- 🔧 `03_qsfp_prbs\` — 手搭 Native PHY,连接/参数全对,停在 fitter 物理布局(不建议再走)
- 📄 memory `msa2020-gxt-transceiver.md` — 全部踩坑与正解已记录
