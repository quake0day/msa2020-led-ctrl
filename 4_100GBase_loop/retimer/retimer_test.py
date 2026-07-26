# -*- coding: utf-8 -*-
"""
retimer_test.py -- QSFP0 Retimer/I2C 初始化状态检查 (实验4 阶段2)
用法: python retimer_test.py   (板卡已烧录 retimer_init.sof)
流程: 连接 ISSP(RTMR) → 读初始化状态 → 可选软复位重跑
读的是 DS250DF810 + FPC202 经 I2C 上电初始化的完成标志与 QSFP 端口状态。
"""
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                ".." , "..", "2_EMIF"))
from led_gui import SysCon


class Retimer(SysCon):
    def connect(self, progress=None):
        for attempt in range(15):
            if self.tcl("get_service_paths issp").strip():
                break
            if progress:
                progress("扫描 JTAG... (%d)" % attempt)
            time.sleep(2)
        else:
            raise RuntimeError("未发现 ISSP (确认已烧录 retimer_init.sof)")
        n = int(self.tcl("llength [get_service_paths issp]"))
        self.issp = None
        for k in range(n):
            ptxt = self.tcl("lindex [get_service_paths issp] %d" % k)
            if "RTMR" in ptxt or "_RTMR" in ptxt:
                self.issp = "[lindex [get_service_paths issp] %d]" % k
                break
        if self.issp is None:                       # 回退: 取第一个
            self.issp = "[lindex [get_service_paths issp] 0]"
        self.tcl("open_service issp " + self.issp)
        p = self.rd()
        if (p >> 24) & 0xFF != 0x52:
            raise RuntimeError("签名 0x%02X != 0x52" % ((p >> 24) & 0xFF))

    def wr(self, v):
        self.tcl("issp_write_source_data %s 0x%X" % (self.issp, v))

    def rd(self):
        return int(self.tcl("issp_read_probe_data " + self.issp).strip(), 0)

    def status(self):
        p = self.rd()
        return dict(ds_ready=p & 1, fpc_ready=(p >> 1) & 1,
                    init_ready=(p >> 2) & 1, sys_reset=(p >> 3) & 1,
                    in_a=(p >> 4) & 0xF, in_b=(p >> 8) & 0xF,
                    in_c=(p >> 12) & 0xF,
                    modprsl=(p >> 16) & 0x3, intl=(p >> 18) & 0x3)


def main():
    sc = Retimer()
    try:
        sc.start()
        sc.tcl("expr 0", timeout=90)
        sc.connect(progress=print)
        print("已连接 (签名 0x52)")

        print("软复位重跑初始化...")
        sc.wr(0x1)
        time.sleep(0.3)
        sc.wr(0x0)
        time.sleep(1.0)                             # 等 I2C 序列跑完

        s = sc.status()
        print("DS250DF810 初始化: %s" % ("完成" if s["ds_ready"] else "未完成"))
        print("FPC202     初始化: %s" % ("完成" if s["fpc_ready"] else "未完成"))
        print("整体 init_ready : %s" % ("是" if s["init_ready"] else "否"))
        print("QSFP modprsl(在位) : 0b%s (0=模块插入)" % format(s["modprsl"], "02b"))
        print("QSFP intl(中断)    : 0b%s" % format(s["intl"], "02b"))
        print("FPC202 in_a/b/c    : %X / %X / %X" % (s["in_a"], s["in_b"], s["in_c"]))

        ok = s["ds_ready"] and s["fpc_ready"]
        print("\n=== %s ===" % ("Retimer/I2C 初始化全部通过!!"
                                if ok else "初始化未完成, 检查 I2C 上拉/器件供电"))
    finally:
        sc.close()


if __name__ == "__main__":
    main()
