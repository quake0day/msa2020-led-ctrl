# MSA-2020 DDR4 帧缓存 (PCIe → DDR4)

把**已校准的 DDR4 EMIF**(项目 2 `jtag_sys`)接到 **PCIe BAR**(项目 3 框架),
让主机通过 PCIe 直接读写板载 DDR4 —— 作为视频加速器的**帧缓存**。

```
host --PCIe--> hip_ast --TLP--> pcie_axil_master --AXI-Lite(pcie_clk)-->
     axil_ddr_bridge  --跨时钟CDC-->  Avalon-MM(clk100M) --> jtag_sys.mem_* --> DDR4
```

- EMIF 内部再把 Avalon 跨到 DDR4 用户时钟(qsys 处理),桥只需跨 `pcie_clk ↔ clk100M`。
- 单发握手 + toggle 同步,简单可靠(帧缓存吞吐足够)。
- 复用同一个 100MHz 用户时钟(AD6)既做 PCIe housekeeping 又做 EMIF 系统时钟。
- **只允许一个 Reset Release IP**:本设计用 `jtag_sys` 内部那个,`ninit_done` 输出
  同时驱动 EMIF 复位和 PCIe housekeeping PLL 复位(已删掉 PCIe 侧独立的 reset_release)。

## BAR0 内存映射 (256KB)

| addr[17] | 区域 | 说明 |
|----------|------|------|
| 0 | **DDR4 数据窗口** (128KB) | `am_address = {PAGE, addr[16:0]}` |
| 1 | 寄存器 | 见下 |

| 偏移 | 名称 | 说明 |
|------|------|------|
| `0x20000` | PAGE   | RW `am_address[35:17]`(选 DDR4 页 / 哪条 DIMM) |
| `0x20004` | STATUS | R bit0=DIMM0 cal_ok, bit1=DIMM1 cal_ok |
| `0x2000C` | ID     | R `0x44445242` "DDRB" |

DDR4 am 地址:DIMM0 CH0 从 `0x0` 起,DIMM1 CH1 从 `0x4_0000_0000` 起(每条 16GB)。

## 主机使用

```bash
sudo bash host/pcie_fix_bridge_window.sh                 # 若 BAR 读全 f
sudo python3 host/ddr4_fb_test.py 0000:01:00.0                     # DIMM0 写读回
sudo python3 host/ddr4_fb_test.py 0000:01:00.0 --base 0x400001000  # DIMM1
```

## 构建

```bash
cd 9_ddr4_framebuffer
/h/fpga/quartus/bin64/quartus_sh --flow compile pcie_dma -c pcie_dma
```

## 状态 / 风险

这是四个子系统里**集成度最高**的一个:PCIe Gen3x8 硬核 + 双通道 DDR4 EMIF + CDC 桥
合在一个工程里。关键集成点(单一 Reset Release、共用 100MHz、mem_* 由桥驱动)已处理。
DDR4 本身在项目 2 已实测校准通过(1Rx8,72-bit ECC)。烧录后先确认 `STATUS` 的 cal_ok,
再跑数据窗口读写。
