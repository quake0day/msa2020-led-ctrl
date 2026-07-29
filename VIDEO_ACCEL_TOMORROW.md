# MSA-2020 视频计算加速器 —— 明天上午烧录测试指南

四个子系统各自独立成一个 `.sof`,逐个烧录、逐个测。全部基于已在真机验证过的
PCIe BAR 框架(项目 3)/ DDR4 EMIF(项目 2)。

| # | 目录 | 交付 | 覆盖需求 | .sof |
|---|------|------|----------|------|
| 1 | `7_video_accel` | 视频计算引擎(9 模式) | 颜色空间转换 / 视频滤波(卷积) / AI 前处理 / PCIe 返回 | `output_files/pcie_dma.sof` |
| 2 | `8_dct_codec`   | 8×8 DCT/IDCT 变换核 | H.264/H.265 的变换心脏(编解码器数学核心) | `output_files/pcie_dma.sof` |
| 3 | `9_ddr4_framebuffer` | PCIe→DDR4 帧缓存 | 帧缓存(利用 DDR4) | `output_files/pcie_dma.sof` |

> 完整 H.264/H.265 编解码器无法从零今夜写成(运动估计+CABAC+去块滤波是巨型 IP);
> `8_dct_codec` 交付其数学核心。图像缩放(bilinear)为 `7_video_accel` 的后续模式(待加)。

## 通用流程(每个 .sof 一样)

### 1) 烧录(JTAG 临时配置,不动板上配置 flash)

```bash
# 确认线缆名(MSA 的 Catapult FTDI):
quartus_pgm -l
# 烧录(把 <CABLE> 换成上面列出的名字, 通常 "MSA..." 或索引 1):
quartus_pgm -c 1 -m jtag -o "p;7_video_accel/output_files/pcie_dma.sof"
```

> ⚠️ 只用 `.sof` 走 JTAG **临时配置**,不写 `.jic/.pof` 到配置 flash(避免覆盖板卡出厂配置)。
> 烧录会重配 FPGA → PCIe 链路会重协商,主机侧需要重新枚举(见下)。

### 2) 主机侧枚举 + 修桥窗口

烧录后 FPGA 重配,PCIe 需重新枚举。热重配常把上游桥的预取窗口搞坏 → BAR 读全 `0xffffffff`。
每个工程 `host/` 下都带了修复脚本:

```bash
# 找到设备 (VID 1234):
lspci -d 1234: -nn
# 修桥窗口:
sudo bash 7_video_accel/host/pcie_fix_bridge_window.sh
```

> 冷重启可让 PCIe 回到 Gen3 x8(热重配会降到 Gen1);功能测试热重配即可,跑满带宽再冷启。

### 3) 逐个测试

**① 视频计算引擎**
```bash
sudo python3 7_video_accel/host/video_accel_test.py <BDF>          # 9 模式全自检(位精确对照)
# 真实图片:
sudo python3 7_video_accel/host/video_accel_test.py <BDF> --mode 8 --kernel sobel_x \
     --in in.png --out edge.png --width 128 --height 128
```
预期:`ID=0x56414343 (VACC OK)`,各模式 `mismatch=0 ... OK`,末行 `ALL PASS`。

**② DCT/IDCT 变换核**
```bash
sudo python3 8_dct_codec/host/dct_test.py <BDF> --blocks 4
```
预期:`ID=0x44435438 (DCT8 OK)`,`FDCT ... OK` / `IDCT ... OK`,往返误差为个位数(量化正常)。

**③ DDR4 帧缓存**
```bash
sudo python3 9_ddr4_framebuffer/host/ddr4_fb_test.py <BDF>                    # DIMM0
sudo python3 9_ddr4_framebuffer/host/ddr4_fb_test.py <BDF> --base 0x400001000 # DIMM1
```
预期:`ID=0x44445242 (DDRB OK)`,`cal_ok: DIMM0=1`,`==> PASS`。
若 `cal_ok=0`:检查内存条是否插好(项目 2 已实测校准通过)。

## 排障速查

- BAR 读 `0xffffffff` → 跑 `pcie_fix_bridge_window.sh`(几乎每次热重配都要)。
- `ID` 不对但非全 f → 可能读到别的 BAR/设备,确认 BDF(`lspci -d 1234:`)。
- 设备号不出现 → 检查 `dmesg`,可能需要 `echo 1 > /sys/bus/pci/.../remove` + `echo 1 > /sys/bus/pci/rescan`。
- 每个 `host/` 目录都自带 `pcie_fix_bridge_window.sh`。
