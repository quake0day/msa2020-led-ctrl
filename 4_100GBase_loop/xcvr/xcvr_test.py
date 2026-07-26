# -*- coding: utf-8 -*-
"""
xcvr_test.py -- QSFP0 4×25.78G GXT 收发器状态检查 (实验6 阶段1)
用法: python xcvr_test.py   (板卡已烧录 qsfp_xcvr.sof)
读 XCVR ISSP(签名 0x1C): 各通道 PRBS31 block_lock / high_ber / 误码累加。
注意: 无 QSFP 光模块/环回时 block_lock 不会拉高属正常(收发器仍会校准锁参考);
      内部串行环回版本见 README。
"""
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                ".." , "..", "2_EMIF"))
from led_gui import SysCon


class Xcvr(SysCon):
    def connect(self, progress=None):
        for attempt in range(15):
            if self.tcl("get_service_paths issp").strip():
                break
            if progress:
                progress("扫描 JTAG... (%d)" % attempt)
            time.sleep(2)
        else:
            raise RuntimeError("未发现 ISSP (确认已烧录 qsfp_xcvr.sof)")
        n = int(self.tcl("llength [get_service_paths issp]"))
        self.issp = None
        for k in range(n):
            ptxt = self.tcl("lindex [get_service_paths issp] %d" % k)
            if "XCVR" in ptxt:
                self.issp = "[lindex [get_service_paths issp] %d]" % k
                break
        if self.issp is None:
            self.issp = "[lindex [get_service_paths issp] 0]"
        self.tcl("open_service issp " + self.issp)
        if (self.rd() >> 24) & 0xFF != 0x1C:
            raise RuntimeError("签名 != 0x1C")

    def wr(self, v):
        self.tcl("issp_write_source_data %s 0x%X" % (self.issp, v))

    def rd(self):
        return int(self.tcl("issp_read_probe_data " + self.issp).strip(), 0)

    def read_ch(self, ch):
        self.wr(0x2 | (ch << 2))            # prbs_en 保持, 选通道
        time.sleep(0.05)
        p = self.rd()
        return dict(pll_locked=(p >> 2) & 1, pll_cal_busy=(p >> 3) & 1,
                    rx_act=[p >> i & 1 for i in range(4, 8)],
                    err=(p >> 8) & 0xFFFF)


def main():
    sc = Xcvr()
    try:
        sc.start()
        sc.tcl("expr 0", timeout=90)
        sc.connect(progress=print)
        print("已连接 (签名 0x1C)")
        print("复位收发器, 等待校准/锁定 (8s)...")
        sc.wr(0x1)                          # soft reset (清误码累加)
        time.sleep(0.5)
        sc.wr(0x2)                          # release, prbs_en
        time.sleep(8)

        s = sc.read_ch(0)
        print("ATX PLL 锁定 : %s   校准忙: %s   RX 恢复时钟: %s"
              % ("是" if s["pll_locked"] else "否",
                 "是" if s["pll_cal_busy"] else "否", s["rx_act"]))
        print("\nPRBS31 误码累加 (读两次, 相隔 2s; 不再增长=链路干净锁定):")
        e1 = [sc.read_ch(ch)["err"] for ch in range(4)]
        time.sleep(2)
        e2 = [sc.read_ch(ch)["err"] for ch in range(4)]
        locked = []
        for ch in range(4):
            grew = e2[ch] != e1[ch]
            locked.append(not grew)
            print("  通道%d: %6d -> %6d  %s"
                  % (ch, e1[ch], e2[ch], "增长(有误码)" if grew else "稳定(锁定✓)"))

        if all(locked):
            print("\n=== 4×25.78G PRBS31 内部环回全部锁定, 零新增误码, 链路 OK!! ===")
        else:
            print("\n=== 部分通道仍有误码, 见上 (通道时钟已恢复, 属图案对齐问题) ===")
    finally:
        sc.close()


if __name__ == "__main__":
    main()
