# -*- coding: utf-8 -*-
"""
spd_read.py -- 经 ISSP -> mm_bridge -> altera_avalon_i2c 读 DIMM SPD
用法: python spd_read.py   (板卡需已烧录单通道诊断版 led_ctrl.sof)
I2C csr 基址 0x80000000; SPD 器件地址 0x50~0x53 自动扫描。
"""
import sys
import time

sys.path.insert(0, '.')
from led_gui import SysCon

I2C = 0x200000000
TFR_CMD, RX_DATA, CTRL, ISR, STATUS = 0x00, 0x04, 0x10 - 8, 0x10, 0x14
# 寄存器字节偏移 (字地址x4): TFR=0x00 RX=0x04 CTRL=0x08 ISER=0x0C ISR=0x10
# STATUS=0x14 TFR_LVL=0x18 RX_LVL=0x1C SCL_LOW=0x20 SCL_HIGH=0x24 SDA_HOLD=0x28
R = dict(TFR=0x00, RX=0x04, CTRL=0x08, ISER=0x0C, ISR=0x10, STATUS=0x14,
         TFR_LVL=0x18, RX_LVL=0x1C, SCL_LOW=0x20, SCL_HIGH=0x24, SDA_HOLD=0x28)
STA, STO = 1 << 9, 1 << 8


class Spd:
    def __init__(self, sc):
        self.sc = sc

    def w(self, off, val):
        self.sc.mem_write(I2C + off, val)

    def r(self, off):
        return self.sc.mem_read(I2C + off)

    def setup(self):
        self.w(R["CTRL"], 0)              # 先禁用
        self.w(R["SCL_LOW"], 500)         # 100MHz -> 100kHz
        self.w(R["SCL_HIGH"], 500)
        self.w(R["SDA_HOLD"], 60)
        self.w(R["ISR"], 0x3FF)           # 清中断状态
        self.w(R["CTRL"], 1)              # 使能

    def probe(self, dev):
        """探测器件: 发 START+addr(w) + STOP, 看 NACK 中断位"""
        self.w(R["ISR"], 0x3FF)
        self.w(R["TFR"], STA | STO | (dev << 1) | 0)
        time.sleep(0.05)
        isr = self.r(R["ISR"])
        return not (isr & 0x4)            # bit2 = NACK

    def read_byte(self, dev, addr):
        self.w(R["ISR"], 0x3FF)                   # 清状态
        self.w(R["TFR"], STA | (dev << 1) | 0)   # START + 写
        self.w(R["TFR"], addr & 0xFF)             # 字节地址
        self.w(R["TFR"], STA | (dev << 1) | 1)   # 重复START + 读
        self.w(R["TFR"], STO)                     # 读1字节 + STOP
        for _ in range(60):
            if self.r(R["RX_LVL"]) > 0:
                return self.r(R["RX"]) & 0xFF
            time.sleep(0.02)
        raise TimeoutError("I2C 读超时 dev=0x%02X addr=%d (ISR=0x%X)"
                           % (dev, addr, self.r(R["ISR"])))


def main():
    sc = SysCon()
    try:
        sc.start()
        sc.tcl("expr 0", timeout=90)
        sc.connect(progress=print)
        s = Spd(sc)
        s.setup()
        print("I2C 已配置 (100kHz), 扫描 SPD 器件 0x50~0x53 ...")
        found = None
        for dev in range(0x50, 0x54):
            ok = s.probe(dev)
            print("  0x%02X: %s" % (dev, "ACK ✓" if ok else "无响应"))
            if ok and found is None:
                found = dev
        if found is None:
            print("未发现 SPD 器件 (DIMM 的 SPD 可能不在这条 I2C 总线上)")
            return
        print("读取 0x%02X 的 SPD 关键字节..." % found)
        # 基本识别
        for off, name in [(0, "SPD字节数"), (2, "内存类型(0x0C=DDR4)"),
                          (3, "模组类型(0x01=RDIMM)"), (4, "颗粒密度/bank"),
                          (5, "行列地址"), (12, "模组组织(rank/位宽)"),
                          (13, "总线宽度")]:
            v = s.read_byte(found, off)
            print("  [%3d] 0x%02X  %s" % (off, v, name))
        # RCD/SPD 参数字节 (映射 EMIF MEM_DDR4_SPD_*)
        print("RCD/终端参数字节 (填 EMIF MEM_DDR4_SPD_*):")
        for off in [133, 134, 135, 136, 137, 138, 139,
                    140, 141, 142, 143, 144, 145, 148, 149, 152, 155]:
            v = s.read_byte(found, off)
            print("  MEM_DDR4_SPD_%d = %d  (0x%02X)" % (off, v, v))
    finally:
        sc.close()


if __name__ == "__main__":
    main()
