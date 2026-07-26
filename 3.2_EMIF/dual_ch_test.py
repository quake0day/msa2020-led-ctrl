# -*- coding: utf-8 -*-
import sys, time
from led_gui import SysCon
sc = SysCon()
try:
    sc.start(); sc.tcl("expr 0", timeout=90)
    sc.connect(progress=print)
    print("已连接 (签名 0x5A)")
    ok, fail, pwr = sc.ddr_cal_status()
    for i in (0, 1):
        st = "成功 ✓" if ok[i] else ("失败 ✗" if fail[i] else "—(未报告)")
        print("DDR4 DIMM%d (CH%d) 校准: %s" % (i, i, st))
    if not sc.mem:
        print("无内存通道"); sys.exit()
    print("\n双通道读写自检:")
    for name, base in [("DIMM0 CH0", 0x100), ("DIMM1 CH1", 0x400000100)]:
        bad = 0
        for i in range(16):
            sc.mem_write(base + i*4, (0xA5000000 + i*0x11111) & 0xFFFFFFFF)
        for i in range(16):
            want = (0xA5000000 + i*0x11111) & 0xFFFFFFFF
            got = sc.mem_read(base + i*4)
            if got != want:
                bad += 1
                if bad <= 2: print("  %s 不符[0x%X]: %08X != %08X" % (name, base+i*4, got, want))
        print("  %s: %d/16 字通过 %s" % (name, 16-bad, "✓" if bad==0 else "✗"))
finally:
    sc.close()
