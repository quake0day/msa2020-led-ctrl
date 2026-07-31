#!/usr/bin/env python3
# =====================================================================
# MSA-2020 H.264 编码器 —— 主机端: 喂一帧 YUV -> PCIe BAR -> 取 H.264 码流
#   1) 读入/生成一帧 YUV420  2) MB-tiled 排布写入输入缓冲
#   3) 设 QP/尺寸/intra, 触发, 轮询 done  4) 读回 slice-data + 字节数
#   5) 软件打包 (SPS+PPS+slice-header) -> out.264  6) 可选 ffmpeg 解码验证
#
#   用法:
#     sudo python3 h264_encode.py <BDF> --w 96 --h 64 [--in frame.yuv|img.png] [--qp 27] [--out out.264]
#     BAR 若读 0xffffffff 先跑 pcie_fix_bridge_window.sh
# =====================================================================
import sys, os, mmap, struct, time, argparse, subprocess
sys.path.insert(0, os.path.dirname(__file__))
import h264_pack

CTRL,STATUS,QP,FLAGS,XTOTAL,YTOTAL,BYTES,IDREG = 0x00,0x04,0x08,0x0C,0x10,0x14,0x18,0x3C
IN_BASE, OUT_BASE = 0x10000, 0x20000

def clamp(v): return 0 if v<0 else (255 if v>255 else int(v))

def load_frame(path, W, H):
    if path is None:                                   # 合成图 (与 gen_yuv 同款)
        Y=[[clamp(((x*255)//(W-1))//2 + (100 if (W//4<=x<3*W//4 and H//4<=y<3*H//4) else 0) + 20)
            for x in range(W)] for y in range(H)]
        U=[[clamp(128+(x-W//4)*2) for x in range(W//2)] for y in range(H//2)]
        V=[[clamp(128+(y-H//4)*2) for x in range(W//2)] for y in range(H//2)]
        return Y,U,V
    if path.lower().endswith((".png",".jpg",".jpeg",".bmp")):
        from PIL import Image
        im=Image.open(path).convert("YCbCr").resize((W,H))
        px=list(im.getdata())
        Y=[[px[y*W+x][0] for x in range(W)] for y in range(H)]
        U=[[px[(2*y)*W+2*x][1] for x in range(W//2)] for y in range(H//2)]
        V=[[px[(2*y)*W+2*x][2] for x in range(W//2)] for y in range(H//2)]
        return Y,U,V
    d=open(path,"rb").read()                            # 裸 YUV420
    Y=[[d[y*W+x] for x in range(W)] for y in range(H)]
    off=W*H; cw,ch=W//2,H//2
    U=[[d[off+y*cw+x] for x in range(cw)] for y in range(ch)]
    off+=cw*ch
    V=[[d[off+y*cw+x] for x in range(cw)] for y in range(ch)]
    return Y,U,V

def tile(Y,U,V,W,H):                                    # -> MB-tiled 32-bit 字列表
    def w32(a,b,c,d): return (a<<24)|(b<<16)|(c<<8)|d
    MBX,MBY=W//16,H//16; words=[]
    for mby in range(MBY):
        for mbx in range(MBX):
            for r in range(16):
                for c in range(0,16,4):
                    words.append(w32(*[Y[mby*16+r][mbx*16+c+i] for i in range(4)]))
            for auv in range(16):
                us=[];vs=[]
                for k in range(4):
                    idx=auv*4+k; rr=idx//8; cc=idx%8
                    us.append(U[mby*8+rr][mbx*8+cc]); vs.append(V[mby*8+rr][mbx*8+cc])
                words.append(w32(us[0],vs[0],us[1],vs[1])); words.append(w32(us[2],vs[2],us[3],vs[3]))
    return words, MBX, MBY

class Dev:
    def __init__(s,bdf):
        p="/sys/bus/pci/devices/%s/resource0"%bdf
        s.m=mmap.mmap(os.open(p,os.O_RDWR|os.O_SYNC),os.path.getsize(p),prot=mmap.PROT_READ|mmap.PROT_WRITE)
    def wr(s,o,v): s.m.seek(o); s.m.write(struct.pack('<I',v&0xffffffff)); s.m.flush()
    def rd(s,o): s.m.seek(o); return struct.unpack('<I',s.m.read(4))[0]

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("bdf")
    ap.add_argument("--w",type=int,required=True); ap.add_argument("--h",type=int,required=True)
    ap.add_argument("--in",dest="inp",default=None); ap.add_argument("--qp",type=int,default=27)
    ap.add_argument("--out",default="out.264"); ap.add_argument("--verify",action="store_true")
    a=ap.parse_args()
    assert a.w%16==0 and a.h%16==0, "宽高须为16倍数"
    d=Dev(a.bdf)
    idv=d.rd(IDREG)
    print("h264_wrap ID=0x%08x (%s)"%(idv,"H264 OK" if idv==0x48323634 else "!! 非 H264, 检查 BAR/桥"))
    if idv==0xffffffff: print("BAR=0xffffffff, 先跑 pcie_fix_bridge_window.sh"); sys.exit(1)

    Y,U,V=load_frame(a.inp,a.w,a.h)
    words,MBX,MBY=tile(Y,U,V,a.w,a.h)
    print("帧 %dx%d = %dx%d MB, 输入 %d 字"%(a.w,a.h,MBX,MBY,len(words)))
    for i,wd in enumerate(words): d.wr(IN_BASE+i*4, wd)     # 写输入
    d.wr(QP,a.qp); d.wr(FLAGS,0x2); d.wr(XTOTAL,MBX-1); d.wr(YTOTAL,MBY-1)
    d.wr(CTRL,1)                                            # 触发
    t0=time.time()
    while time.time()-t0<5:
        st=d.rd(STATUS)
        if (st&2) and not (st&1): break
    else: print("编码超时 STATUS=0x%08x"%d.rd(STATUS)); sys.exit(2)
    nb=d.rd(BYTES); print("编码完成: %d slice 字节, %d 周期"%(nb, 0))
    raw=bytearray()                                        # 读码流
    for i in range((nb+3)//4):
        w=d.rd(OUT_BASE+i*4); raw+=struct.pack('<I',w)
    raw=bytes(raw[:nb])
    open(a.out+".slice","wb").write(raw)
    # 软件打包
    S=h264_pack.last_set_bit_index(raw); sd=h264_pack.bits_of(raw)[:S]
    sps=h264_pack.nal(0x67,h264_pack.make_sps(MBX,MBY))
    pps=h264_pack.nal(0x68,h264_pack.make_pps(a.qp))
    slc=h264_pack.nal(0x65,h264_pack.make_idr_slice(a.qp,sd))
    open(a.out,"wb").write(sps+pps+slc)
    print("打包 -> %s (%d 字节, slice %d bits)"%(a.out,len(sps)+len(pps)+len(slc),S))
    if a.verify:
        r=subprocess.run(["ffprobe","-v","error","-show_entries","stream=codec_name,width,height",
                          "-of","default=noprint_wrappers=1",a.out],capture_output=True,text=True)
        print("ffprobe:",r.stdout.strip().replace("\n"," "), r.stderr.strip())

if __name__=="__main__": main()
