# -*- coding: utf-8 -*-
"""
gen_ddr_pins.py -- 从 Microsoft_A-2020_PINDEF.xlsx 提取 DDR4 引脚约束,
翻译成 led_ctrl 顶层端口名 (ddr4_<槽>_*), 写入 led_ctrl.qsf

用法: python gen_ddr_pins.py <PINDEF.xlsx路径> all      # 4 槽全部 (侦察版)
      python gen_ddr_pins.py <PINDEF.xlsx路径> <0-3>    # 单槽
IO 电平/端接由 EMIF IP 自动施加, 此处只提供引脚位置。
"""
import re
import sys

import openpyxl

SCALAR = {"ck", "ck_n", "act_n", "cke", "cs_n", "odt", "reset_n",
          "oct_rzqin", "ref_clk"}
SCALAR_NAME = {"oct_rzqin": "rzqin"}          # 其余同名
VECTOR = {"a": 17, "ba": 2, "bg": 2, "dq": 72, "dqs": 9, "dqs_n": 9}
SKIP = {"dbi_n", "par", "alert_n"}            # DM/DBI 关闭; parity/alert 关闭

# EMIF 对 A/C lane 内引脚索引有硬性放置规则, PINDEF 的 ba/bg 顺序需按
# fitter 报告的合法位置对调 (bank 位置换功能透明)。按槽位记录:
FIXUPS = {
    0: {"ba[0]": "PIN_AL4", "ba[1]": "PIN_AL1",
        "bg[0]": "PIN_AL2", "bg[1]": "PIN_AR9"},
    1: {"ba[0]": "PIN_H6", "ba[1]": "PIN_G4",
        "bg[0]": "PIN_G5", "bg[1]": "PIN_M10"},
    2: {"ba[0]": "PIN_BA20", "ba[1]": "PIN_AW20",
        "bg[0]": "PIN_AV20", "bg[1]": "PIN_BA22"},
    3: {"ba[0]": "PIN_H27", "ba[1]": "PIN_G27",
        "bg[0]": "PIN_F27", "bg[1]": "PIN_N30"},
}

# 注: PINDEF PIN 表 LED 列的 12V/SWITCH_GD/DDR_LDO_GD 实测均非 FPGA 用户 IO
# (D17 位置非法, D10/D11 与 DDR 通道引脚冲突), 不可作为状态输入使用
POWER_PINS = []

BEGIN, END = "# ---- DDR4 PINS BEGIN ----", "# ---- DDR4 PINS END ----"


def extract(xlsx, slot):
    ws = openpyxl.load_workbook(xlsx, data_only=True)["ASSIGNMENTS"]
    rows = list(ws.iter_rows(values_only=True))
    start = next(i for i, r in enumerate(rows)
                 if "DDR4 CH0" in " ".join(str(v) for v in r if v is not None))
    pre = "ddr4_%d_" % slot
    out, counts = [], {}
    for r in rows[start:]:
        v = r[slot + 1] if len(r) > slot + 1 else None
        if not v or "set_location_assignment" not in str(v):
            continue
        m = re.search(r"(PIN_\w+)\s+-to\s+ddr4_mem\[\d\]\.(\w+)(?:\[(\d+)\])?",
                      str(v))
        if not m:
            continue
        pin, sig = m.group(1), m.group(2)
        if sig in SKIP:
            continue
        if sig in VECTOR:
            i = counts.get(sig, 0)
            counts[sig] = i + 1
            if i >= VECTOR[sig]:
                continue                       # a[17] 等超宽位跳过
            short = "%s[%d]" % (sig, i)
            pin = FIXUPS.get(slot, {}).get(short, pin)
            out.append("set_location_assignment %s -to %s%s[%d]"
                       % (pin, pre, sig, i))
        elif sig in SCALAR:
            out.append("set_location_assignment %s -to %s%s"
                       % (pin, pre, SCALAR_NAME.get(sig, sig)))
        else:
            print("警告: 未识别信号", sig)
    return out


def main():
    xlsx, arg = sys.argv[1], sys.argv[2]
    slots = [0, 1, 2, 3] if arg == "all" else [int(arg)]
    lines = []
    for s in slots:
        lines += ["# -- 丝印槽位 DIMM%d --" % s] + extract(xlsx, s)
    lines += ["# -- 电源状态指示 --"]
    lines += ["set_instance_assignment -name IO_STANDARD \"1.8 V\" -to %s" % n
              for _, n in POWER_PINS]
    lines += ["set_location_assignment %s -to %s" % (p, n)
              for p, n in POWER_PINS]
    print("共 %d 条约束 (%s)" % (len(lines), arg))
    with open("led_ctrl.qsf", encoding="utf-8") as f:
        qsf = f.read()
    block = "%s\n%s\n%s" % (BEGIN, "\n".join(lines), END)
    if BEGIN in qsf:
        qsf = re.sub(re.escape(BEGIN) + r".*?" + re.escape(END), block,
                     qsf, flags=re.S)
    else:
        qsf = qsf.rstrip() + "\n\n" + block + "\n"
    with open("led_ctrl.qsf", "w", encoding="utf-8") as f:
        f.write(qsf)
    print("已写入 led_ctrl.qsf")


if __name__ == "__main__":
    main()
