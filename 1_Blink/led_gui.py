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
        self.issp = None
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
        self.issp = "[lindex [get_service_paths issp] 0]"
        self.tcl("open_service issp " + self.issp)
        probe = self.read_probe()
        if (probe >> 24) & 0xFF != SIGNATURE:
            raise RuntimeError("探针签名 = 0x%02X, 不是 0x5A, "
                               "板内可能不是 led_ctrl 工程" % ((probe >> 24) & 0xFF))

    def write_source(self, val):
        self.tcl("issp_write_source_data %s 0x%X" % (self.issp, val))

    def read_probe(self):
        return int(self.tcl("issp_read_probe_data " + self.issp).strip(), 0)

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
