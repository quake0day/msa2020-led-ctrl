# -*- coding: utf-8 -*-
"""
xcvr_test.py -- QSFP0 收发器 PRBS 环回测试 (实验3)
用法: python xcvr_test.py   (板卡已烧录 qsfp_prbs.sof)
流程: 连接 ISSP(XCV) → 开内部串行环回 → 清零计数 → 观察锁定与误码
"""
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "02_ddr4_emif"))
from led_gui import SysCon


class Xcvr(SysCon):
    def connect_xcvr(self, progress=None):
        for attempt in range(15):
            if self.tcl("get_service_paths issp").strip():
                break
            if progress:
                progress("扫描 JTAG... (%d)" % attempt)
            time.sleep(2)
        else:
            raise RuntimeError("未发现 ISSP (确认已烧录 qsfp_prbs.sof)")
        n = int(self.tcl("llength [get_service_paths issp]"))
        for k in range(n):
            ptxt = self.tcl("lindex [get_service_paths issp] %d" % k)
            if "_XCV" in ptxt:
                self.xcv = "[lindex [get_service_paths issp] %d]" % k
                break
        else:
            raise RuntimeError("未找到 XCV 通道 ISSP")
        self.tcl("open_service issp " + self.xcv)
        p = self.rd()
        if (p >> 88) & 0xFF != 0x3C:
            raise RuntimeError("签名 0x%02X != 0x3C" % ((p >> 88) & 0xFF))

    def wr(self, v):
        self.tcl("issp_write_source_data %s 0x%X" % (self.xcv, v))

    def rd(self):
        return int(self.tcl("issp_read_probe_data " + self.xcv).strip(), 0)

    def status(self, ch=0):
        self.wr(0x1 | (ch << 3))          # 保持环回, 选通道
        time.sleep(0.05)
        p = self.rd()
        return dict(tx_ready=[p >> i & 1 for i in range(0, 4)],
                    rx_ready=[p >> i & 1 for i in range(4, 8)],
                    locked=[p >> i & 1 for i in range(8, 12)],
                    err_seen=[p >> i & 1 for i in range(12, 16)],
                    err_count=(p >> 16) & 0xFFFFFFFF,
                    pll=[p >> 48 & 1, p >> 49 & 1])


def main():
    sc = Xcvr()
    try:
        sc.start()
        sc.tcl("expr 0", timeout=90)
        sc.connect_xcvr(progress=print)
        print("已连接 (签名 0x3C)")

        print("开启内部串行环回 + 清零计数...")
        sc.wr(0x3)          # lpbk_en + cnt_clear
        time.sleep(0.5)
        sc.wr(0x1)          # 释放 clear, 保持环回
        time.sleep(2)

        s = sc.status()
        print("ATX PLL 锁定: PLL0=%d PLL1=%d" % (s["pll"][0], s["pll"][1]))
        print("TX 就绪: %s" % s["tx_ready"])
        print("RX 就绪: %s" % s["rx_ready"])
        print("CDR 锁定: %s" % s["locked"])
        print("误码标志: %s" % s["err_seen"])
        for ch in range(4):
            st = sc.status(ch)
            print("  通道%d 误码计数: %d" % (ch, st["err_count"]))

        ok = (all(s["rx_ready"]) and all(s["locked"])
              and not any(sc.status(0)["err_seen"]))
        print("\n=== %s ===" % ("PRBS 环回全部通过!! 4×25.78G 链路 OK"
                                if ok else "存在异常, 见上方状态"))
    finally:
        sc.close()


if __name__ == "__main__":
    main()
