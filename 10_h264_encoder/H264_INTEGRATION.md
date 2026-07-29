# 开源 H.264 编码器 (xk264) 在 MSA-2020 上的集成

## 选型(诚实)
- **H.265/HEVC**:开源硬件里**没有**可直接综合的 RTL 编码器。唯一开源硬件 HEVC 编码器
  [uvgKvazaarHW](https://ultravideo.fi/uvgkvazaarhw.html) 走 **HLS(Catapult)**流程,不是拿来即综合的 Verilog。
  → 现实交付 = **H.264**。
- **H.264**:选 [**xk264**](https://github.com/openasic-org/xk264)(复旦 VIPcore,Verilog RTL,
  H.264 Baseline,1080p60,完整 intra 9 模式 + inter(1/4 亚像素)+ CAVLC + 去块滤波)。
  备选 [hardh264](https://github.com/bcattle/hardh264)(VHDL,BSD,已在 Altera Cyclone III 验证,但较简化)。

## ★已达成:xk264 在 Stratix 10 上综合通过★
```
Quartus Prime Synthesis was successful. 0 errors
Implemented 200,681 logic cells | 3,162 M20K | 72 DSP
```
占 `1SG280`(~933K ALM,数千 M20K/DSP)的一**小部分** → PCIe+DDR4 外壳有充足余量。
工程:`10_h264_encoder/`(qsf 列全部 rtl_fpga + mem_fpga)。综合:`quartus_syn h264enc -c h264enc`。

## 移植改动(为什么/怎么做)
xk264 是 ASIC 导向,两处需 FPGA 化(**没动原 clone,改动都在派生副本**):
1. **存储原语**:`lib/behave/mem/{ram_1p,ram_2p,rom_1p}.v` 用内部三态 `oen?'bz:data`(FPGA 无内部三态)。
   → 写了接口完全一致的 FPGA 库 `mem_fpga/xk264_mem_fpga.v`(标准 M20K 模板,恒驱动寄存输出),qsf 里用它替换。
   (`rf_1p/rf_2p` 原本就无三态,一并重写保持一致。)
2. **异步复位块**:`rtl/db/db_control.v:935` 的 `always@(posedge clk or negedge rst)` 里
   `if(!rst) ram_out<=0;` 后跟了**裸 `if(state==Y)`** 而非 `else if` —— Quartus 报 19544(且这本是潜在 bug:
   复位时两分支都触发)。→ 派生副本 `rtl_fpga/` 里改成 `else if`。qsf 指向 `rtl_fpga`。

## 顶层接口 → 映射到本框架
`module top` 的端口正好落在已建的 PCIe BAR + DDR4 通路上:
| xk264 端口 | 方向 | 集成到 |
|-----------|------|--------|
| `clk, rst_n` | in | PCIe user clock / 复位 |
| `sys_qp[5:0]`,`sys_mode`,`sys_x_total`,`sys_y_total` | in | **控制寄存器**(BAR) |
| `rdata_i[63:0]`,`rvalid_i`,`rinc_o` | 原始 YUV 输入 | host 经 PCIe 写**输入帧缓冲**,喂 8 像素/拍 |
| `wdata_o[7:0]`,`winc_o`,`wfull_i` | H.264 字节流输出 | 存**输出码流缓冲**(BAR 读) |
| `ext_mb_x/y_o`,`ext_start_o`,`ext_mode_o[2:0]`,`ext_data_o[127:0]` | out | **参考帧存储控制器** |
| `ext_done_i`,`ext_ren_i`,`ext_wen_i`,`ext_addr_i[3:0]`,`ext_data_i[127:0]` | in | ← 存储控制器 |

## ext_ 参考帧协议(集成的关键难点)
编码器发 `ext_start_o` + `ext_mb_x/y_o` + `ext_mode_o`,外部存储控制器需:
- 按 mode(读参考 / 写重建)对该 MB 顺序搬 16 个 4×4 子块(每次 128-bit),
  驱动 `ext_ren_i/ext_wen_i/ext_addr_i`,读时喂 `ext_data_i`、写时收 `ext_data_o`,完成拉 `ext_done_i`。
- 地址结构(见 `sim/top_testbench/tb_top.v` 的行为模型 `ref_mem[1<<25]`):
  `{frame_num[0](双缓冲), luma/chroma, mb_y, mb_x, 4x4_idx, ...}`。
- 硬件实现 = 把 tb 的 `#10` 行为模型翻成**时钟 FSM**,背后接:
  - **小分辨率(≤VGA)**:片上 M20K(参考帧几十~几百 KB,S10 绰绰有余)→ 自包含,不依赖 DDR4。
  - **大分辨率**:接 DDR4(复用 `9_ddr4_framebuffer` 的 Avalon 通路)。
- 纯 **intra 模式**(`sys_mode`)不需要参考帧 → ext_ 可最小化,是最快跑通的第一步。

## 状态与剩余工作(诚实)
- ✅ 开源核在 S10 综合通过(本目录)。✅ FPGA 存储库。✅ 移植补丁。✅ 集成架构确定。
- ⏳ **外壳 `h264_wrap`**(控制寄存器 + 输入/输出缓冲 + ext_ 时钟 FSM)—— 控制/IO 部分直接可写;
  ext_ 控制器要对着 `rtl/top/mem_arbiter.v` 精确对时序,是**多天级功能 bring-up**(尤其验证"输出确是合法 H.264 码流")。
- 建议路线:**先 intra-only + 片上参考帧**做最小可跑闭环(host 喂一帧 YUV → 取回 H.264 NAL),
  再加 inter + DDR4 参考帧扩到大分辨率。

## 授权(务必知悉)
- **xk264 文件头**:未经复旦 VIPcore 书面同意不得修改/再分发(仓库另称可 research/production 用)——
  **自用/研究没问题**;产品化或再分发需联系 fanyibo@fudan.edu.cn。移植补丁都放在派生副本,原 clone 未改。
- **H.264 专利**:MPEG-LA 专利池,**商用出货需专利授权**(自研/研究通常不涉及)。
