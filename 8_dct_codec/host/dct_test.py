#!/usr/bin/env python3
# =====================================================================
# MSA-2020 DCT/IDCT 变换核 —— 主机测试 / 位精确验证
#   与 gen_dct.py 共用同一整数系数表 -> HW 与参考应逐位相同。
#
#   用法:
#     sudo python3 dct_test.py <BDF>            # FDCT + IDCT 自检 + 往返
#     sudo python3 dct_test.py <BDF> --blocks 4
# =====================================================================
import sys, os, mmap, struct, time, argparse
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import gen_dct   # fdct_block / idct_block / C

CTRL,STATUS,MODE,COUNT,PARAM0 = 0x00,0x04,0x08,0x14,0x18
CHECKSUM,CYCLES,BLOCKS,ID = 0x20,0x24,0x28,0x3C
IN_BASE, OUT_BASE = 0x10000, 0x20000

class Dev:
    def __init__(self, bdf):
        p="/sys/bus/pci/devices/%s/resource0"%bdf
        self.sz=os.path.getsize(p); self.fd=os.open(p,os.O_RDWR|os.O_SYNC)
        self.m=mmap.mmap(self.fd,self.sz,prot=mmap.PROT_READ|mmap.PROT_WRITE)
    def wr(self,o,v): self.m.seek(o); self.m.write(struct.pack('<I',v&0xffffffff)); self.m.flush()
    def rd(self,o): self.m.seek(o); return struct.unpack('<I',self.m.read(4))[0]
    def rds(self,o):
        v=self.rd(o); return v-0x100000000 if v&0x80000000 else v
    def wr_words(self,base,words):
        for i,w in enumerate(words): self.m.seek(base+4*i); self.m.write(struct.pack('<i',int(w)))
        self.m.flush()
    def rd_words(self,base,n,signed=False):
        out=[]
        for i in range(n):
            self.m.seek(base+4*i); v=struct.unpack('<I',self.m.read(4))[0]
            out.append(v-0x100000000 if (signed and v&0x80000000) else v)
        return out
    def run(self,mode,nblocks,lshift,timeout=3.0):
        self.wr(MODE,mode); self.wr(COUNT,nblocks); self.wr(PARAM0,1 if lshift else 0)
        self.wr(CTRL,1); t0=time.time()
        while time.time()-t0<timeout:
            st=self.rd(STATUS)
            if (st&0x2) and not (st&0x1): return
        raise RuntimeError("timeout STATUS=0x%08x"%self.rd(STATUS))

def clip(v,lo,hi): return lo if v<lo else (hi if v>hi else v)

def flat_blocks_to_grid(vals):   # 64 vals -> 8x8
    return [[vals[r*8+c] for c in range(8)] for r in range(8)]
def grid_to_flat(g): return [g[r][c] for r in range(8) for c in range(8)]

def test_fdct(dev, blocks, lshift=True):
    # 输入像素 0..255
    inp=[]
    for b in range(blocks):
        for i in range(64): inp.append((b*17 + i*3 + (i*i)%13) % 256)
    dev.wr_words(IN_BASE, inp)
    dev.run(0, blocks, lshift)
    got = dev.rd_words(OUT_BASE, blocks*64, signed=True)
    # 参考
    bad=0; sw_ck=0
    for b in range(blocks):
        x = flat_blocks_to_grid(inp[b*64:b*64+64])
        xs = [[x[r][c]-(128 if lshift else 0) for c in range(8)] for r in range(8)]
        F = gen_dct.fdct_block(xs)
        ref = grid_to_flat(F)
        for i in range(64):
            sw_ck ^= (ref[i] & 0xffffffff)
            if (got[b*64+i] & 0xffffffff) != (ref[i] & 0xffffffff): bad+=1
    hw_ck=dev.rd(CHECKSUM)
    ok = (bad==0 and hw_ck==(sw_ck & 0xffffffff))
    print("  FDCT  %d blk: mismatch=%d hw_ck=0x%08x sw_ck=0x%08x cyc=%d %s"
          %(blocks,bad,hw_ck,sw_ck&0xffffffff,dev.rd(CYCLES),"OK" if ok else "*** FAIL ***"))
    return ok, inp

def test_idct(dev, blocks, coeffs_src, lshift=True):
    # 输入 = FDCT 系数; 反变换应还原像素
    dev.wr_words(IN_BASE, coeffs_src)
    dev.run(1, blocks, lshift)
    got = dev.rd_words(OUT_BASE, blocks*64, signed=True)
    bad=0; sw_ck=0
    for b in range(blocks):
        f = flat_blocks_to_grid(coeffs_src[b*64:b*64+64])
        X = gen_dct.idct_block(f)
        ref=[]
        for r in range(8):
            for c in range(8):
                v = X[r][c] + (128 if lshift else 0)
                if lshift: v = clip(v,0,255)
                ref.append(v)
        for i in range(64):
            sw_ck ^= (ref[i] & 0xffffffff)
            if (got[b*64+i] & 0xffffffff) != (ref[i] & 0xffffffff): bad+=1
    hw_ck=dev.rd(CHECKSUM)
    ok=(bad==0 and hw_ck==(sw_ck&0xffffffff))
    print("  IDCT  %d blk: mismatch=%d hw_ck=0x%08x sw_ck=0x%08x cyc=%d %s"
          %(blocks,bad,hw_ck,sw_ck&0xffffffff,dev.rd(CYCLES),"OK" if ok else "*** FAIL ***"))
    return ok, got

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("bdf")
    ap.add_argument("--blocks",type=int,default=4); a=ap.parse_args()
    d=Dev(a.bdf)
    idv=d.rd(ID)
    print("dct_accel ID=0x%08x (%s)"%(idv,"DCT8 OK" if idv==0x44435438 else "!! not DCT8 — check BAR/bridge"))
    if idv==0xffffffff:
        print("BAR=0xffffffff — run pcie_fix_bridge_window.sh first"); sys.exit(1)
    ok1, pixels = test_fdct(d, a.blocks, True)
    # 读回 HW 的 FDCT 系数 (在 out_mem 中), 作为 IDCT 输入做端到端往返
    coeffs = d.rd_words(OUT_BASE, a.blocks*64, signed=True)
    ok2, recon = test_idct(d, a.blocks, coeffs, True)
    # 往返误差 (IDCT(FDCT(x)) vs x)
    maxerr=max(abs((recon[i]&0xffffffff) - pixels[i]) for i in range(a.blocks*64))
    print("  round-trip max|IDCT(FDCT(x))-x| = %d (量化引入的小误差属正常)"%maxerr)
    print("==> %s"%("ALL PASS" if (ok1 and ok2) else "SOME FAILED"))
    sys.exit(0 if (ok1 and ok2) else 2)

if __name__=="__main__": main()
