# MSA-2020 视频编解码变换核 (8×8 DCT / IDCT)

**H.264 / H.265 / JPEG 共用的"变换心脏"**,挂在已验证的 PCIe BAR 框架上。

> ⚠️ 诚实说明:**完整的 H.264/H.265 编解码器无法从零今夜写成** —— 运动估计、CABAC 熵编码、
> 环路去块滤波是业界最大的 IP 之一。本工程交付编解码器的**数学核心**:8×8 二维
> DCT-II 正变换与 IDCT 反变换 + 定点量化标度。要做完整编解码,需集成开源/商用 codec IP。

## 做什么

```
host --PCIe BAR--> in_mem(8x8块) --> dct_accel(行变换->转置->列变换) --> out_mem --PCIe--> host
```

- 正变换 FDCT:像素块(可选电平位移 −128)→ 频域系数。
- 反变换 IDCT:系数 → 像素块(可选 +128 并钳位 0..255)。
- 可分离:先行 1-D DCT 写转置缓冲,再列 1-D DCT。定点 Q13 系数,行后 >>8、列后 >>18。
- 系数表由 `gen_dct.py` 生成(`dct_coef.vh`),**同一张表供 RTL 与主机参考模型** → 逐位可校验。

## BAR0 寄存器

| 偏移 | 名称 | 说明 |
|------|------|------|
| `0x00` | CTRL   | W bit0=start |
| `0x04` | STATUS | R busy/done, magic 0x4443 |
| `0x08` | MODE   | RW 0=FDCT 1=IDCT |
| `0x14` | COUNT  | RW 8×8 块数 (≤256) |
| `0x18` | PARAM0 | RW bit0=电平位移 |
| `0x20` | CHECKSUM / `0x24` CYCLES / `0x28` BLOCKS | R |
| `0x3C` | ID     | R `0x44435438` "DCT8" |

数据缓冲:输入 `0x10000`,输出 `0x20000`,每值 1 个 32-bit 字(有符号),块 b 占 `[b*64, b*64+63]`。

## 主机使用

```bash
sudo python3 gen_dct.py                          # (可选) 重新生成/自检系数, 往返误差应=0
sudo python3 host/dct_test.py 0000:01:00.0        # FDCT + IDCT + 端到端往返
```

## 构建

```bash
cd 8_dct_codec
/h/fpga/quartus/bin64/quartus_sh --flow compile pcie_dma -c pcie_dma
```
