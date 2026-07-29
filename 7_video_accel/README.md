# MSA-2020 视频计算加速器 (video_accel)

在已验证的 **PCIe BAR 框架**(项目 3 的 `hip_ast + Corundum TLP → AXI-Lite`)之上,
把 BAR0 后端从一块 256KB RAM 换成一个**视频计算引擎**。主机通过 BAR0 写入一帧像素、
选模式、触发,再读回结果 —— 全程走 PCIe。

VID/DID = `0x1234 / 0x1002`。器件 `1SG280LN2F43E2VG`(Stratix 10)。

## 数据通路

```
host  --PCIe TLP-->  hip_ast  -->  Corundum pcie_s10_if  -->  pcie_axil_master_minimal
      --AXI-Lite-->  video_accel { 寄存器 + 输入BRAM + 计算FSM + 输出BRAM }
```

## BAR0 内存映射 (256KB, 18-bit)

| 区域 | 地址 | 说明 |
|------|------|------|
| 寄存器 | `0x00000`–`0x0FFFF` | 见下表 (idx = addr[5:2]) |
| 输入缓冲 `in_mem`  | `0x10000`–`0x1FFFF` | 16384 像素 (每像素 1 个 32-bit 字, 0RGB) |
| 输出缓冲 `out_mem` | `0x20000`–`0x2FFFF` | 16384 像素 (计算结果) |

像素格式:`{8'X, R[23:16], G[15:8], B[7:0]}`。

### 寄存器

| 偏移 | 名称 | R/W | 说明 |
|------|------|-----|------|
| `0x00` | CTRL     | W | bit0 = start(触发一次计算) |
| `0x04` | STATUS   | R | bit0=busy, bit1=done, [31:16]=0x5641 |
| `0x08` | MODE     | RW| 计算模式(见下) |
| `0x0C` | WIDTH    | RW| 图像宽(像素) — 卷积用 |
| `0x10` | HEIGHT   | RW| 图像高 — 卷积用 |
| `0x14` | COUNT    | RW| 处理的像素/字数 (≤16384) |
| `0x18` | PARAM0   | RW| 依模式(见下) |
| `0x1C` | PARAM1   | RW| 依模式 |
| `0x2C` | PARAM2   | RW| 卷积: c8 + 右移量[12:8] |
| `0x30` | PARAM3   | RW| 卷积: bit0=取绝对值(边缘) |
| `0x20` | CHECKSUM | R | 所有输出字的 XOR(免读全缓冲即可校验) |
| `0x24` | CYCLES   | R | 本次计算周期数 |
| `0x28` | PIXELS   | R | 已处理像素数 |
| `0x3C` | ID       | R | `0x56414343` "VACC" |

### 模式

| MODE | 功能 | 参数 |
|------|------|------|
| 0 | 直通 (copy) | — |
| 1 | **RGB→YUV** (BT.601) | — |
| 2 | **YUV→RGB** (BT.601) | — |
| 3 | **灰度** (亮度) | — |
| 4 | 反色 | — |
| 5 | **AI 归一化** → int8 `(c-mean)*scale>>8` | P0={_,mR,mG,mB}, P1=scale(Q0.8) |
| 6 | 二值化(阈值) | P0=阈值 |
| 7 | 亮度/对比度 `(c*contrast>>6)+bright` | P0=bright(int8), P1=contrast(Q2.6) |
| 8 | **3×3 卷积** (模糊/锐化/Sobel边缘/浮雕) | P0=c0..c3, P1=c4..c7, P2=c8+shift, P3=abs |

覆盖用户需求中的:**图像预处理(颜色空间转换)**、**视频滤波(卷积)**、
**AI 推理前处理(归一化)**、**PCIe 返回结果**。

> DCT/IDCT 变换核在同级 `8_dct_codec`,DDR4 帧缓存在 `9_ddr4_framebuffer`。
> 完整 H.264/H.265 编解码器无法从零今夜写成(运动估计+熵编码+去块滤波是巨型 IP),
> `8_dct_codec` 交付其数学核心 DCT/IDCT(H.264/H.265/JPEG 共用的变换心脏)。

## 主机使用

BAR 若读到 `0xffffffff`(remove+rescan 后桥预取窗口失效),先修桥窗口:

```bash
sudo bash host/pcie_fix_bridge_window.sh
```

跑全部模式自检(带位精确软件参考对照):

```bash
sudo python3 host/video_accel_test.py 0000:01:00.0
```

单模式 / 真实图片(需 Pillow):

```bash
sudo python3 host/video_accel_test.py 0000:01:00.0 --mode 3 --in in.png --out gray.png --width 128 --height 128
sudo python3 host/video_accel_test.py 0000:01:00.0 --mode 8 --kernel sobel_x --in in.png --out edge.png --width 128 --height 128
```

## 构建

```bash
cd 7_video_accel
/h/fpga/quartus/bin64/quartus_sh --flow compile pcie_dma -c pcie_dma   # → output_files/pcie_dma.sof
```

烧录(JTAG,不动配置 flash):`quartus_pgm` 用 `.sof` 走 JTAG 临时配置。
