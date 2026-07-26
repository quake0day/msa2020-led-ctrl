# -*- coding: utf-8 -*-
"""
led_gui.py -- MSA-2020 LED 控制台 (独立 GUI 程序, ISSP 通道版)

用法:  python led_gui.py
前提:  1) 板卡 USB 已连接, 已烧录 led_ctrl.sof
       2) FT232H 驱动 + jtag_hw_microsoft_catapult.dll 已按 Onboard_jtag/readme.txt 安装
       3) 本机装有 Quartus (用到 syscon 作为 JTAG 通道, 界面上不可见)

原理:  GUI 启动一个隐藏的 system-console -cli 子进程, 经 ISSP
       (In-System Sources & Probes) 通道读写 FPGA。
       注: 板卡的 Catapult 定制 JTAG 驱动不支持 System Console 的
       JTAG-Avalon 流式传输 (会挂死), 因此使用单次移位的 ISSP 通道。

ISSP 位定义 (与 led_ctrl_core.v 一致):
  source[15:0]: [2:0] 模式 | [11:3] 手动LED | [14:12] 速度 | [15] 接管使能
  probe[31:0] : [8:0] LED | [11:9] 生效灯效 | [14:12] 模式 | [15] issp接管
                [19:16] 心跳 | [31:24] 签名 0x5A
"""

import os
import queue
import subprocess
import threading
import time
import tkinter as tk
from tkinter import ttk, messagebox

MODES = ["自动轮换", "计数器闪烁", "流水灯", "呼吸灯", "波浪呼吸", "手动直控"]
PATS = ["计数器闪烁", "流水灯", "呼吸灯", "波浪呼吸", "手动"]
SIGNATURE = 0x5A

SYSCON_CANDIDATES = [
    os.environ.get("SYSCON_PATH", ""),
    r"H:\fpga\syscon\bin\system-console.exe",
    r"C:\intelFPGA_pro\23.3\syscon\bin\system-console.exe",
]


# ======================================================================
# 后端: 管理 system-console -cli 子进程, 经 ISSP 读写
# ======================================================================
class SysCon:
    BEGIN, OK, ERR, END = "@@BEGIN@@", "@@OK@@", "@@ERR@@", "@@END@@"

    def __init__(self):
        self.proc = None
        self.lines = queue.Queue()
        self.issp = None       # LED 控制通道 (instance_id=LED)
        self.mem = None        # 内存命令通道 (instance_id=MEM)
        self.mem_seq = 0
        self.lock = threading.Lock()

    @staticmethod
    def find_exe():
        for p in SYSCON_CANDIDATES:
            if p and os.path.isfile(p):
                return p
        raise FileNotFoundError(
            "未找到 system-console.exe, 请设置环境变量 SYSCON_PATH")

    def start(self):
        exe = self.find_exe()
        si = subprocess.STARTUPINFO()
        si.dwFlags |= subprocess.STARTF_USESHOWWINDOW  # 隐藏子进程窗口
        self.proc = subprocess.Popen(
            [exe, "-cli"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True, encoding="utf-8", errors="replace",
            startupinfo=si)
        threading.Thread(target=self._reader, daemon=True).start()

    def _reader(self):
        for line in self.proc.stdout:
            self.lines.put(line.rstrip("\r\n"))
        self.lines.put(None)   # 子进程退出

    def tcl(self, cmd, timeout=30):
        """执行一条 Tcl 命令, 返回结果字符串; 出错抛异常"""
        with self.lock:
            if not self.proc or self.proc.poll() is not None:
                raise RuntimeError("后端进程未运行")
            wrapped = ('puts "%s"; if {[catch {%s} __r]} '
                       '{puts "%s$__r"} else {puts "%s$__r"}; puts "%s"'
                       % (self.BEGIN, cmd, self.ERR, self.OK, self.END))
            self.proc.stdin.write(wrapped + "\n")
            self.proc.stdin.flush()
            result, seen = None, False
            while True:
                try:
                    line = self.lines.get(timeout=timeout)
                except queue.Empty:
                    raise TimeoutError("等待 system-console 响应超时: " + cmd)
                if line is None:
                    raise RuntimeError("system-console 已退出")
                if line.endswith(self.BEGIN):
                    seen = True
                elif seen and line.startswith(self.OK):
                    result = line[len(self.OK):]
                elif seen and line.startswith(self.ERR):
                    raise RuntimeError(line[len(self.ERR):])
                elif seen and line.endswith(self.END):
                    return result

    # ---------------- 板卡操作 (ISSP) ----------------
    def connect(self, retries=15, interval=2.0, progress=None):
        # JTAG 链枚举需要时间, 轮询等待 issp 服务出现 (最长约 30 秒)
        for attempt in range(retries):
            paths = self.tcl("get_service_paths issp")
            if paths and paths.strip():
                break
            if progress and attempt % 3 == 2:
                progress("仍在扫描 JTAG 链... (%d/%d)" % (attempt + 1, retries))
            time.sleep(interval)
        else:
            raise RuntimeError("未发现 ISSP 服务。请依次检查: "
                               "1) 板卡 USB 已插好 "
                               "2) FTDI D2XX 驱动已装 "
                               "3) jtag_hw_microsoft_catapult.dll 已复制到 "
                               "quartus\\bin64 "
                               "4) 已用 Programmer 烧录 led_ctrl.sof")
        # 两个 ISSP 实例: 按 instance_id 后缀区分 LED / MEM
        n = int(self.tcl("llength [get_service_paths issp]"))
        for k in range(n):
            ref = "[lindex [get_service_paths issp] %d]" % k
            ptxt = self.tcl("lindex [get_service_paths issp] %d" % k)
            if "_LED" in ptxt:
                self.issp = ref
            elif "_MEM" in ptxt:
                self.mem = ref
        if not self.issp:
            raise RuntimeError("未找到 LED 通道 ISSP 实例")
        self.tcl("open_service issp " + self.issp)
        probe = self.read_probe()
        if (probe >> 24) & 0xFF != SIGNATURE:
            raise RuntimeError("探针签名 = 0x%02X, 不是 0x5A, "
                               "板内可能不是 led_ctrl 工程" % ((probe >> 24) & 0xFF))
        if self.mem:
            self.tcl("open_service issp " + self.mem)
            mp = int(self.tcl("issp_read_probe_data " + self.mem).strip(), 0)
            if (mp >> 56) & 0xFF != 0xA5:
                self.mem = None      # 旧固件没有内存通道

    def ddr_cal_status(self):
        """返回 (ok[4], fail[4], pwr[3]) 各通道校准与电源状态"""
        p = int(self.tcl("issp_read_probe_data " + self.mem).strip(), 0)
        ok = [(p >> (48 + i)) & 1 for i in range(4)]
        fail = [(p >> (52 + i)) & 1 for i in range(4)]
        pwr = [(p >> (44 + i)) & 1 for i in range(3)]   # 12V, SWITCH, DDR_LDO
        return ok, fail, pwr

    def ddr_usrclk_alive(self):
        """返回各通道 usr_clk 活动计数 [4]; 读两次若增长=该EMIF PLL已锁定"""
        p = int(self.tcl("issp_read_probe_data " + self.mem).strip(), 0)
        return [(p >> (80 + i * 4)) & 0xF for i in range(4)]

    def ddr_refclk_alive(self):
        """返回各通道 ref_clk 输入活动计数 [4]; 增长=参考时钟脚有信号"""
        p = int(self.tcl("issp_read_probe_data " + self.mem).strip(), 0)
        return [(p >> (64 + i * 4)) & 0xF for i in range(4)]

    def write_source(self, val):
        self.tcl("issp_write_source_data %s 0x%X" % (self.issp, val))

    def read_probe(self):
        return int(self.tcl("issp_read_probe_data " + self.issp).strip(), 0)

    # ---------------- 内存读写 (经 issp_mem_bridge FSM) ----------------
    def mem_cmd(self, we, addr, wdata=0):
        """执行一次 32bit 内存读/写, addr 为字节地址(自动对齐到字)"""
        if not self.mem:
            raise RuntimeError("固件无内存通道 (需烧录含 issp_mem_bridge 的版本)")
        self.mem_seq = self.mem_seq % 255 + 1          # 1..255 循环, 避开 0
        wa = addr >> 2                                 # 34位字地址
        word = ((self.mem_seq << 64) | ((wa >> 30 & 0xF) << 72)
                | (int(we) << 62)
                | ((wa & 0x3FFFFFFF) << 32) | (wdata & 0xFFFFFFFF))
        self.tcl("issp_write_source_data %s 0x%X" % (self.mem, word))
        for _ in range(40):                            # 等 FSM 完成 (通常首轮即毕)
            p = int(self.tcl("issp_read_probe_data " + self.mem).strip(), 0)
            if (p >> 32) & 0xFF == self.mem_seq:
                return p & 0xFFFFFFFF
            time.sleep(0.05)
        raise TimeoutError("内存命令超时 (seq=%d)" % self.mem_seq)

    def mem_read(self, addr):
        return self.mem_cmd(0, addr)

    def mem_write(self, addr, val):
        self.mem_cmd(1, addr, val)

    def close(self):
        try:
            if self.proc and self.proc.poll() is None:
                self.proc.stdin.write("exit\n")
                self.proc.stdin.flush()
                self.proc.wait(timeout=5)
        except Exception:
            pass
        if self.proc:
            # 必须杀整个进程树: system-console 的 java 子进程若成为孤儿,
            # 会一直持有 JTAG 链的锁, 导致之后谁都扫不到板卡
            subprocess.run(["taskkill", "/T", "/F", "/PID", str(self.proc.pid)],
                           capture_output=True)


# ======================================================================
# 界面
# ======================================================================
class App:
    def __init__(self, root):
        self.root = root
        self.sc = SysCon()
        self.connected = False
        self.auto_poll = tk.BooleanVar(value=True)
        # 本地控制状态 (打包进 source 字)
        self.cur_mode, self.cur_manual, self.cur_speed = 0, 0, 0
        root.title("MSA-2020 LED 控制台")
        root.resizable(False, False)
        self._build()
        root.protocol("WM_DELETE_WINDOW", self.on_quit)
        self.log("正在启动 JTAG 后端 (system-console), 首次约需 10~30 秒...")
        threading.Thread(target=self._startup, daemon=True).start()

    # ---------------- 界面搭建 ----------------
    def _build(self):
        pad = dict(padx=8, pady=4)

        top = ttk.Frame(self.root); top.pack(fill="x", **pad)
        self.lb_conn = ttk.Label(top, text="● 未连接", foreground="red")
        self.lb_conn.pack(side="left")
        ttk.Button(top, text="重新连接", command=self.reconnect).pack(side="right")

        g1 = ttk.LabelFrame(self.root, text="LED Pattern"); g1.pack(fill="x", **pad)
        for i, name in enumerate(MODES[:5]):
            ttk.Button(g1, text=name, width=10,
                       command=lambda v=i: self.set_mode(v)
                       ).grid(row=i // 3, column=i % 3, padx=4, pady=4)
        ttk.Button(g1, text="全灭", width=10,
                   command=lambda: self.set_manual(0)
                   ).grid(row=1, column=2, padx=4, pady=4)

        g2 = ttk.LabelFrame(self.root, text="速度档位"); g2.pack(fill="x", **pad)
        self.speed = tk.IntVar(value=0)
        for v in range(6):
            ttk.Radiobutton(g2, text="x%d" % (1 << v), value=v,
                            variable=self.speed,
                            command=lambda: self.set_speed(self.speed.get())
                            ).pack(side="left", padx=6)

        g3 = ttk.LabelFrame(self.root, text="手动直控"); g3.pack(fill="x", **pad)
        self.cbs = []
        for i in range(8, -1, -1):
            var = tk.BooleanVar()
            ttk.Checkbutton(g3, text=str(i), variable=var).pack(side="left", padx=2)
            self.cbs.insert(0, var)          # cbs[i] 对应 LEDi
        ttk.Button(g3, text="应用", command=self.apply_manual).pack(side="right", padx=6)

        g4 = ttk.LabelFrame(self.root, text="板卡 LED 实时状态 (LED8 → LED0)")
        g4.pack(fill="x", **pad)
        self.canvas = tk.Canvas(g4, width=330, height=40, highlightthickness=0)
        self.canvas.pack(side="left", padx=8, pady=4)
        self.dots = []
        for i in range(9):                    # 左=LED8 ... 右=LED0
            x = 12 + i * 34
            d = self.canvas.create_oval(x, 8, x + 24, 32,
                                        fill="#404040", outline="#202020")
            self.canvas.create_text(x + 12, 36, text=str(8 - i), font=("Arial", 7))
            self.dots.append(d)
        ttk.Checkbutton(g4, text="自动刷新", variable=self.auto_poll
                        ).pack(side="right", padx=6)
        self.lb_mode = ttk.Label(g4, text="")
        self.lb_mode.pack(side="right", padx=6)

        g5 = ttk.LabelFrame(self.root,
                            text="内存读写 (当前: 片内RAM 64KB; EMIF 就绪后同界面读写 DDR4)")
        g5.pack(fill="x", **pad)
        ttk.Label(g5, text="地址(hex)").grid(row=0, column=0, padx=4, pady=4)
        self.en_addr = ttk.Entry(g5, width=12)
        self.en_addr.insert(0, "0")
        self.en_addr.grid(row=0, column=1, padx=2)
        ttk.Label(g5, text="数据(hex)").grid(row=0, column=2, padx=4)
        self.en_data = ttk.Entry(g5, width=12)
        self.en_data.grid(row=0, column=3, padx=2)
        ttk.Button(g5, text="读取", width=6, command=self.mem_read_clicked
                   ).grid(row=0, column=4, padx=4)
        ttk.Button(g5, text="写入", width=6, command=self.mem_write_clicked
                   ).grid(row=0, column=5, padx=4)
        ttk.Button(g5, text="自检(16字)", command=self.mem_selftest
                   ).grid(row=0, column=6, padx=4)

        self.txt = tk.Text(self.root, height=6, width=52, state="disabled",
                           font=("Consolas", 9))
        self.txt.pack(fill="x", **pad)

    # ---------------- 后端交互 ----------------
    def _startup(self):
        try:
            self.sc.start()
            self.sc.tcl("expr 0")            # 等待控制台就绪
            self.log("JTAG 后端已就绪, 正在连接板卡...")
            self._connect()
        except Exception as e:
            self.log("启动失败: %s" % e)

    def _connect(self):
        if getattr(self, "_connecting", False):
            self.log("连接进行中, 请稍候...")
            return
        self._connecting = True
        try:
            self.sc.connect(progress=self.log)
            self.connected = True
            self.lb_conn.config(text="● 已连接 (签名 0x5A)", foreground="green")
            self.log("已连接 MSA-2020 led_ctrl (ISSP 通道)")
            if self.sc.mem:
                try:
                    ok, fail, pwr = self.sc.ddr_cal_status()
                    self.log("电源: 12V=%d SWITCH=%d DDR_LDO=%d" % tuple(pwr))
                    for i in range(4):
                        st = "成功 ✓" if ok[i] else ("失败 ✗" if fail[i] else "—")
                        self.log("DDR4 DIMM%d 校准: %s" % (i, st))
                except Exception:
                    pass
            if not getattr(self, "_poll_started", False):
                self._poll_started = True
                self.root.after(500, self.poll)
        except Exception as e:
            self.connected = False
            self.lb_conn.config(text="● 未连接", foreground="red")
            self.log("连接失败: %s" % e)
        finally:
            self._connecting = False

    def reconnect(self):
        self.log("重新连接...")
        threading.Thread(target=self._connect, daemon=True).start()

    def _push(self):
        """把本地控制状态打包写入 ISSP source (bit15 置 1 = GUI 接管)"""
        word = (0x8000 | (self.cur_speed << 12)
                | ((self.cur_manual & 0x1FF) << 3) | (self.cur_mode & 7))
        self.sc.write_source(word)

    def _do(self, fn, desc):
        """后台线程执行板卡操作, 避免卡界面"""
        if not self.connected:
            self.log("未连接, 先点 [重新连接]")
            return
        def run():
            try:
                fn()
                if desc:
                    self.log(desc)
            except Exception as e:
                self.log("失败: %s" % e)
        threading.Thread(target=run, daemon=True).start()

    def set_mode(self, v):
        self.cur_mode = v
        self._do(self._push, "模式 → " + MODES[v])

    def set_speed(self, v):
        self.cur_speed = v
        self._do(self._push, "速度 → x%d" % (1 << v))

    def set_manual(self, bits):
        self.cur_manual, self.cur_mode = bits, 5
        self._do(self._push, "手动直控 → " + format(bits, "09b"))

    def apply_manual(self):
        self.set_manual(sum(1 << i for i, v in enumerate(self.cbs) if v.get()))

    # ---------------- 内存页操作 ----------------
    def _hex(self, entry, default=None):
        s = entry.get().strip().replace("0x", "").replace("0X", "")
        if not s:
            if default is None:
                raise ValueError("请输入十六进制数")
            return default
        return int(s, 16)

    def mem_read_clicked(self):
        try:
            addr = self._hex(self.en_addr)
        except ValueError as e:
            self.log("地址无效: %s" % e); return
        def fn():
            v = self.sc.mem_read(addr)
            self.root.after(0, lambda: (self.en_data.delete(0, "end"),
                                        self.en_data.insert(0, "%08X" % v)))
            return v
        self._do(lambda: self.log("读 [0x%08X] = 0x%08X" % (addr, fn())), "")

    def mem_write_clicked(self):
        try:
            addr, val = self._hex(self.en_addr), self._hex(self.en_data)
        except ValueError as e:
            self.log("输入无效: %s" % e); return
        self._do(lambda: self.sc.mem_write(addr, val),
                 "写 [0x%08X] = 0x%08X" % (addr, val))

    def mem_selftest(self):
        def fn():
            # 双通道: DIMM0(CH0) @0x100, DIMM1(CH1) @0x4_0000_0100
            chans = [("DIMM0 CH0", 0x100), ("DIMM1 CH1", 0x400000100)]
            n = 16
            for name, base in chans:
                bad = 0
                for i in range(n):
                    self.sc.mem_write(base + i * 4,
                                      (0xA5000000 + i * 0x11111) & 0xFFFFFFFF)
                for i in range(n):
                    want = (0xA5000000 + i * 0x11111) & 0xFFFFFFFF
                    got = self.sc.mem_read(base + i * 4)
                    if got != want:
                        bad += 1
                        self.log("%s 不符 [0x%X]: 读 %08X 期望 %08X"
                                 % (name, base + i * 4, got, want))
                self.log("%s 自检: %d/%d 字通过%s"
                         % (name, n - bad, n, " ✓" if bad == 0 else " ✗"))
        self._do(fn, "双通道自检启动 (各写16字→读回比对)")

    # ---------------- 状态轮询 ----------------
    def poll(self):
        if self.connected and self.auto_poll.get():
            threading.Thread(target=self._poll_once, daemon=True).start()
        self.root.after(500, self.poll)

    def _poll_once(self):
        try:
            p = self.sc.read_probe()
        except Exception:
            return
        if (p >> 24) & 0xFF != SIGNATURE:
            return
        bits, act, mode = p & 0x1FF, (p >> 9) & 7, (p >> 12) & 7
        def update():
            for i in range(9):               # dots[0]=LED8 ... dots[8]=LED0
                on = (bits >> (8 - i)) & 1
                self.canvas.itemconfig(self.dots[i],
                                       fill="#30ff60" if on else "#404040")
            self.lb_mode.config(text="%s | %s" % (
                MODES[mode] if mode < 6 else "?",
                PATS[act] if act < 5 else "?"))
        self.root.after(0, update)

    # ---------------- 其他 ----------------
    def log(self, msg):
        def w():
            self.txt.config(state="normal")
            self.txt.insert("end", msg + "\n")
            self.txt.see("end")
            self.txt.config(state="disabled")
        self.root.after(0, w)

    def on_quit(self):
        try:
            if self.connected:
                self.sc.write_source(0)      # 退出时交还板卡控制权
        except Exception:
            pass
        self.sc.close()
        self.root.destroy()


if __name__ == "__main__":
    root = tk.Tk()
    try:
        App(root)
        root.mainloop()
    except FileNotFoundError as e:
        messagebox.showerror("错误", str(e))
