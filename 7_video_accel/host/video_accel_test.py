#!/usr/bin/env python3
# =====================================================================
# MSA-2020 视频计算加速器 —— 主机测试 / 验证工具
#   通过 PCIe BAR0 (resource0 mmap) 驱动 video_accel。
#
#   用法:
#     sudo python3 video_accel_test.py <BDF>                 # 跑全部模式自检
#     sudo python3 video_accel_test.py <BDF> --mode 1        # 单模式
#     sudo python3 video_accel_test.py <BDF> --mode 3 \
#            --in in.png --out gray.png                       # 真实图片
#
#   先确保 BAR 可读 (若读 0xffffffff 先跑 ../../3_PCIE_DMA/host/pcie_fix_bridge_window.sh)
# =====================================================================
import sys, os, mmap, struct, time, argparse

# ---- 寄存器偏移 ----
CTRL, STATUS, MODE, WIDTH, HEIGHT, COUNT = 0x00,0x04,0x08,0x0C,0x10,0x14
PARAM0, PARAM1, CHECKSUM, CYCLES, PIXELS = 0x18,0x1C,0x20,0x24,0x28
PARAM2, PARAM3, ID = 0x2C,0x30,0x3C
IN_BASE  = 0x10000
OUT_BASE = 0x20000
MODES = {0:"passthrough",1:"RGB->YUV",2:"YUV->RGB",3:"grayscale",
         4:"invert",5:"AI-normalize",6:"threshold",7:"bright/contrast",
         8:"conv3x3"}

# 常用 3x3 卷积核 (系数, 右移量, 是否取绝对值)
CONV_KERNELS = {
    "blur":    ([1,1,1, 1,1,1, 1,1,1], 3, 0),   # 盒式模糊 (约 /8)
    "sharpen": ([0,-1,0, -1,5,-1, 0,-1,0], 0, 0),
    "sobel_x": ([-1,0,1, -2,0,2, -1,0,1], 0, 1), # 边缘(取绝对值)
    "sobel_y": ([-1,-2,-1, 0,0,0, 1,2,1], 0, 1),
    "emboss":  ([-2,-1,0, -1,1,1, 0,1,2], 0, 0),
    "identity":([0,0,0, 0,1,0, 0,0,0], 0, 0),
}

class VideoAccel:
    def __init__(self, bdf):
        path = "/sys/bus/pci/devices/%s/resource0" % bdf
        self.size = os.path.getsize(path)
        self.fd = os.open(path, os.O_RDWR | os.O_SYNC)
        self.m = mmap.mmap(self.fd, self.size, prot=mmap.PROT_READ|mmap.PROT_WRITE)
    def wr(self, off, val):
        self.m.seek(off); self.m.write(struct.pack('<I', val & 0xffffffff)); self.m.flush()
    def rd(self, off):
        self.m.seek(off); return struct.unpack('<I', self.m.read(4))[0]
    def wr_buf(self, base, words):
        for i,w in enumerate(words):
            self.m.seek(base + 4*i); self.m.write(struct.pack('<I', int(w) & 0xffffffff))
        self.m.flush()
    def rd_buf(self, base, n):
        out = []
        for i in range(n):
            self.m.seek(base + 4*i); out.append(struct.unpack('<I', self.m.read(4))[0])
        return out
    def run(self, mode, count, p0=0, p1=0, width=0, height=0, timeout=2.0):
        self.wr(MODE, mode); self.wr(COUNT, count)
        self.wr(PARAM0, p0); self.wr(PARAM1, p1)
        self.wr(WIDTH, width); self.wr(HEIGHT, height)
        self.wr(CTRL, 1)                       # trigger
        t0 = time.time()
        while time.time() - t0 < timeout:
            st = self.rd(STATUS)
            if (st & 0x2) and not (st & 0x1):  # done && !busy
                return
        raise RuntimeError("compute timeout, STATUS=0x%08x" % self.rd(STATUS))

# ---------- 位精确软件参考模型 (与 RTL 定点完全一致) ----------
def clip(v, lo, hi): return lo if v < lo else (hi if v > hi else v)
def sat8(v):  return clip(v,0,255)
def sat8s(v): return clip(v,-128,127) & 0xFF

def ref_pixel(mode, px, p0, p1):
    R,G,B = (px>>16)&0xFF, (px>>8)&0xFF, px&0xFF
    if mode == 0: return px & 0xFFFFFFFF
    if mode == 1:
        Y = sat8((77*R+150*G+29*B) >> 8)
        U = sat8(((-43*R-85*G+128*B) >> 8) + 128)
        V = sat8(((128*R-107*G-21*B) >> 8) + 128)
        return (Y<<16)|(U<<8)|V
    if mode == 2:
        Y = (px>>16)&0xFF; U=(px>>8)&0xFF; V=px&0xFF
        r = sat8(Y + ((359*(V-128)) >> 8))
        g = sat8(Y - ((88*(U-128)+183*(V-128)) >> 8))
        b = sat8(Y + ((454*(U-128)) >> 8))
        return (r<<16)|(g<<8)|b
    if mode == 3:
        y = sat8((77*R+150*G+29*B) >> 8); return (y<<16)|(y<<8)|y
    if mode == 4:
        return (px & 0xFF000000) | ((~px) & 0xFFFFFF)
    if mode == 5:
        mR,mG,mB = (p0>>16)&0xFF,(p0>>8)&0xFF,p0&0xFF; s = p1 & 0xFF
        oR=sat8s(((R-mR)*s)>>8); oG=sat8s(((G-mG)*s)>>8); oB=sat8s(((B-mB)*s)>>8)
        return (oR<<16)|(oG<<8)|oB
    if mode == 6:
        y = sat8((77*R+150*G+29*B) >> 8); return 0x00FFFFFF if y >= (p0 & 0xFF) else 0
    if mode == 7:
        c = p1 & 0xFF; br = p0 & 0xFF
        if br & 0x80: br -= 256
        oR=sat8(((R*c)>>6)+br); oG=sat8(((G*c)>>6)+br); oB=sat8(((B*c)>>6)+br)
        return (oR<<16)|(oG<<8)|oB
    return px

def conv_params(coeffs, shift, absmode):
    b = [c & 0xFF for c in coeffs]  # int8 -> byte
    p0 = b[0] | b[1]<<8 | b[2]<<16 | b[3]<<24
    p1 = b[4] | b[5]<<8 | b[6]<<16 | b[7]<<24
    p2 = b[8] | (shift & 0x1F)<<8
    p3 = 1 if absmode else 0
    return p0, p1, p2, p3

def ref_conv(px, w, h, coeffs, shift, absmode):
    # px: 行主序 uint32 数组; 返回灰度卷积结果 (与 RTL 位精确)
    def luma(v):
        R,G,B=(v>>16)&0xFF,(v>>8)&0xFF,v&0xFF
        return sat8((77*R+150*G+29*B)>>8)
    out=[]
    for y in range(h):
        for x in range(w):
            acc=0; k=0
            for dy in (-1,0,1):
                for dx in (-1,0,1):
                    ny = min(max(y+dy,0),h-1); nx = min(max(x+dx,0),w-1)
                    c = coeffs[k]          # CONV_KERNELS 已是有符号 int, 直接用
                    acc += c * luma(px[ny*w+nx]); k+=1
            v = (abs(acc)>>shift) if absmode else (acc>>shift)
            o = sat8(v)
            out.append((o<<16)|(o<<8)|o)
    return out

def test_pattern(n):
    # 渐变 + 彩条, 覆盖各通道范围
    px = []
    for i in range(n):
        R=(i*7)&0xFF; G=(i*3+80)&0xFF; B=(i*13+30)&0xFF
        px.append((R<<16)|(G<<8)|B)
    return px

def img_to_words(path, w, h):
    from PIL import Image
    im = Image.open(path).convert("RGB").resize((w,h))
    px=[];
    for (r,g,b) in list(im.getdata()): px.append((r<<16)|(g<<8)|b)
    return px
def words_to_img(words, w, h, path):
    from PIL import Image
    im = Image.new("RGB",(w,h)); data=[]
    for v in words: data.append(((v>>16)&0xFF,(v>>8)&0xFF,v&0xFF))
    im.putdata(data); im.save(path); print("  saved", path)

def run_mode(va, mode, px, p0, p1, w=0, h=0, verbose=True):
    n = len(px)
    va.wr_buf(IN_BASE, px)
    va.run(mode, n, p0, p1, w, h)
    got = va.rd_buf(OUT_BASE, n)
    exp = [ref_pixel(mode, v, p0, p1) for v in px]
    bad = sum(1 for a,b in zip(got,exp) if a != b)
    cyc = va.rd(CYCLES); hw_ck = va.rd(CHECKSUM)
    sw_ck = 0
    for e in exp: sw_ck ^= e
    ok = (bad == 0) and (hw_ck == sw_ck)
    if verbose:
        print("  mode %d (%-14s): %d px  mismatch=%d  hw_ck=0x%08x sw_ck=0x%08x cyc=%d  %s"
              % (mode, MODES.get(mode,"?"), n, bad, hw_ck, sw_ck, cyc, "OK" if ok else "*** FAIL ***"))
        if bad:
            for i,(a,b) in enumerate(zip(got,exp)):
                if a!=b: print("     [%d] in=0x%08x got=0x%08x exp=0x%08x"%(i,px[i],a,b));
                if i>4: break
    return ok, got

def run_conv(va, px, w, h, kernel_name, verbose=True):
    coeffs, shift, absm = CONV_KERNELS[kernel_name]
    p0,p1,p2,p3 = conv_params(coeffs, shift, absm)
    n = w*h
    va.wr_buf(IN_BASE, px)
    va.wr(PARAM2, p2); va.wr(PARAM3, p3)
    va.run(8, n, p0, p1, w, h, timeout=5.0)
    got = va.rd_buf(OUT_BASE, n)
    exp = ref_conv(px, w, h, coeffs, shift, absm)
    bad = sum(1 for a,b in zip(got,exp) if a!=b)
    hw_ck = va.rd(CHECKSUM); sw_ck=0
    for e in exp: sw_ck ^= e
    ok = (bad==0) and (hw_ck==sw_ck)
    if verbose:
        print("  conv %-9s (%dx%d): mismatch=%d hw_ck=0x%08x sw_ck=0x%08x cyc=%d %s"
              % (kernel_name, w, h, bad, hw_ck, sw_ck, va.rd(CYCLES), "OK" if ok else "*** FAIL ***"))
    return ok, got

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("bdf")
    ap.add_argument("--mode", type=lambda x:int(x,0), default=None)
    ap.add_argument("--count", type=int, default=256)
    ap.add_argument("--param0", type=lambda x:int(x,0), default=0)
    ap.add_argument("--param1", type=lambda x:int(x,0), default=0)
    ap.add_argument("--width", type=int, default=0)
    ap.add_argument("--height", type=int, default=0)
    ap.add_argument("--in", dest="inp", default=None)
    ap.add_argument("--out", dest="outp", default=None)
    ap.add_argument("--kernel", default="sharpen", choices=list(CONV_KERNELS.keys()))
    args = ap.parse_args()

    va = VideoAccel(args.bdf)
    idv = va.rd(ID)
    print("video_accel ID = 0x%08x (%s)" % (idv, "VACC OK" if idv==0x56414343 else "!! not VACC — check BAR/bridge window"))
    if idv == 0xffffffff:
        print("BAR reads 0xffffffff — run pcie_fix_bridge_window.sh first"); sys.exit(1)

    if args.inp:  # 真实图片路径
        w = args.width or 128; h = args.height or 128
        if w*h > 16384:
            print("image too big for 64KB buffer (max 16384 px); shrink w*h"); sys.exit(1)
        px = img_to_words(args.inp, w, h)
        mode = args.mode if args.mode is not None else 3
        if mode == 8:
            ok, got = run_conv(va, px, w, h, args.kernel)
        else:
            # 默认参数(normalize/threshold/bright)给合理值
            p0 = args.param0 or (0x00808080 if mode==5 else (0x80 if mode==6 else 0x00))
            p1 = args.param1 or (0x80 if mode==5 else (0x40 if mode==7 else 0x00))
            ok, got = run_mode(va, mode, px, p0, p1, w, h)
        if args.outp: words_to_img(got, w, h, args.outp)
        sys.exit(0 if ok else 2)

    # 自检: 跑所有模式
    px = test_pattern(args.count)
    modes = [args.mode] if args.mode is not None else list(MODES.keys())
    allok = True
    print("self-test, %d px test pattern:" % len(px))
    for m in modes:
        if m == 8:  # 卷积: 需二维图, 用 16xN 测试图 + 多个核
            w = 16; h = max(2, len(px)//16); img = px[:w*h]
            for kn in ("identity","blur","sharpen","sobel_x","emboss"):
                ok,_ = run_conv(va, img, w, h, kn); allok = allok and ok
            continue
        p0 = 0x00808080 if m==5 else (0x80 if m==6 else 0x0A if m==7 else 0)
        p1 = 0x80 if m==5 else (0x40 if m==7 else 0)
        ok,_ = run_mode(va, m, px, p0, p1)
        allok = allok and ok
    print("==> %s" % ("ALL PASS" if allok else "SOME FAILED"))
    sys.exit(0 if allok else 2)

if __name__ == "__main__":
    main()
