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

## ★功能外壳已实现并仿真验证★(2026-07-29)
"喂 YUV → 取 H.264 码流"的完整链路已在 iverilog 里真正跑通并用 ffmpeg 验证正确:

### 硬/软分工(关键)
`top.v` 里 slice-header 输入 **`sh_we` 接 0** → xk264 硬件**只输出 CAVLC slice-data**,
不产 SPS/PPS/slice-header/起始码。这是 H.264 硬件编码器的标准分工——软件补齐头部:
- **`host/h264_pack.py`**:生成 SPS(Baseline)+PPS+slice-header,**位级拼接**硬件 slice-data,
  加 RBSP trailing + 防竞争字节(00 00 03)+ Annex-B 起始码 → 可被 ffmpeg 解码的 `.264`。

### 输入像素格式(MB-tiled,见 `cur_mb.v`)
MB 光栅序;每 MB = 48 个 64-bit 字:32 luma(光栅 16×16,8 像素/字,首像素在高字节)
+ 16 chroma(每字 `U0 V0 U1 V1 U2 V2 U3 V3` 交织,光栅 8×8)。`host/gen_yuv.py` / `h264_encode.py` 负责排布。

### `ext_` 参考帧控制器(`rtl/h264_ext_mem.v`)
把 xk264 `tb_top.v` 里作者注释掉的时钟 FSM(446–623 行)做成可综合模块,稀疏地址
`{ref_sel,luma/chroma,mb_y,mb_x,cnt}` 换成**紧凑地址** `mb_linear=mb_y*W+mb_x`,片上 M20K
(512KB,支持 ≤512 MB / ~CIF)。8 模式 load/store × Y/UV × deblock/ref。

### `rtl/h264_wrap.v`(PCIe-BAR 外壳)
控制寄存器 + 输入帧 BRAM(host 写→喂 `rdata_i`)+ 码流抓取 BRAM(`winc_o`→host 读)+ 上面的 ext_ 控制器 + xk264 `top`。全在 pcie_clk 单时钟域。

### ✅ 验证结果
- 96×64 I 帧,sim 产 168B slice → 打包 194B `.264` → **ffmpeg 解码成功**;
  重建图 vs 原输入 **Y 平面平均|误差|=0.70**(QP27 有损量化,near-lossless)。
- `h264_wrap` 走 **AXI-Lite 仿真**(模拟 PCIe BAR)→ 输出与直连仿真**逐字节一致**。
- `host/h264_encode.py` 的 MB-tiling 与 `gen_yuv.py` 逐字节一致(离线验证)。

## 剩余工作
- ⏳ **PCIe 工程编译**(`pcie/`,PCIe 硬核 + xk264 + 外壳)→ `.sof`(编译中)。
- ⏳ **真机 bring-up**:烧录 → `h264_encode.py` 喂 YUV → 取 `.264` → ffmpeg 解码验证。
- 后续:P 帧(inter)已在核里,当前外壳按 I 帧闭环;多帧 GOP 需 `frame_parity` 翻转 + 连续喂帧。
  大分辨率(>CIF)把 `ext_` 后端从片上 M20K 换 DDR4(复用 `9_ddr4_framebuffer` 通路)。

## 授权(务必知悉)
- **xk264 文件头**:未经复旦 VIPcore 书面同意不得修改/再分发(仓库另称可 research/production 用)——
  **自用/研究没问题**;产品化或再分发需联系 fanyibo@fudan.edu.cn。移植补丁都放在派生副本,原 clone 未改。
- **H.264 专利**:MPEG-LA 专利池,**商用出货需专利授权**(自研/研究通常不涉及)。
