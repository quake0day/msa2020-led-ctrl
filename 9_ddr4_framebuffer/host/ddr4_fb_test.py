#!/usr/bin/env python3
# =====================================================================
# MSA-2020 DDR4 帧缓存 —— 主机测试
#   PCIe BAR0 -> axil_ddr_bridge -> EMIF -> DDR4。
#   BAR0: addr[17]==0 数据窗口(128KB); addr[17]==1 寄存器。
#     0x20000 PAGE(RW)=am_address[35:17]; 0x20004 STATUS(R) cal_ok; 0x2000C ID(R)
#   DDR4 地址(am, 字节): DIMM0 CH0 ~0x0起, DIMM1 CH1 ~0x400000000起。
# =====================================================================
import sys, os, mmap, struct, time, argparse
PAGE, STATUS, IDREG = 0x20000, 0x20004, 0x2000C
WIN = 0x00000       # 数据窗口基址 (BAR 内), 覆盖 am_address[16:0]

class Dev:
    def __init__(self,bdf):
        p="/sys/bus/pci/devices/%s/resource0"%bdf
        self.sz=os.path.getsize(p); self.fd=os.open(p,os.O_RDWR|os.O_SYNC)
        self.m=mmap.mmap(self.fd,self.sz,prot=mmap.PROT_READ|mmap.PROT_WRITE)
    def wr(self,o,v): self.m.seek(o); self.m.write(struct.pack('<I',v&0xffffffff)); self.m.flush()
    def rd(self,o): self.m.seek(o); return struct.unpack('<I',self.m.read(4))[0]
    def set_am(self, am_byte_addr):
        # am_address = {page[18:0], win[16:0]}; 返回窗口内字节偏移
        page = am_byte_addr >> 17
        self.wr(PAGE, page)
        return WIN + (am_byte_addr & 0x1FFFF)

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("bdf")
    ap.add_argument("--base", type=lambda x:int(x,0), default=0x1000,
                    help="DDR4 起始字节地址(am 空间), DIMM0 用 0x1000, DIMM1 用 0x400001000")
    ap.add_argument("--words", type=int, default=1024)
    a=ap.parse_args()
    d=Dev(a.bdf)
    idv=d.rd(IDREG)
    print("ddr4_fb ID=0x%08x (%s)"%(idv,"DDRB OK" if idv==0x44445242 else "!! not DDRB — check BAR/bridge"))
    if idv==0xffffffff:
        print("BAR=0xffffffff — 先跑 pcie_fix_bridge_window.sh"); sys.exit(1)
    st=d.rd(STATUS)
    print("cal_ok: DIMM0=%d DIMM1=%d  (STATUS=0x%08x)"%(st&1,(st>>1)&1,st))
    if not (st&1):
        print("DDR4 DIMM0 未校准通过 — 检查内存条/时钟"); # 继续也行

    # 写-读回测试 (走 128KB 窗口 + PAGE 选址)
    print("DDR4 写/读回 @am=0x%X, %d words:"%(a.base,a.words))
    bad=0
    for i in range(a.words):
        am = a.base + i*4
        off = d.set_am(am)
        want = (0xC0DE0000 + i*0x101) & 0xffffffff
        d.wr(off, want)
    for i in range(a.words):
        am = a.base + i*4
        off = d.set_am(am)
        got = d.rd(off)
        want = (0xC0DE0000 + i*0x101) & 0xffffffff
        if got != want:
            bad += 1
            if bad<=4: print("  不符[am=0x%X] got=0x%08x want=0x%08x"%(am,got,want))
    print("==> %s (%d/%d mismatch)"%("PASS" if bad==0 else "FAIL", bad, a.words))
    sys.exit(0 if bad==0 else 2)

if __name__=="__main__": main()
