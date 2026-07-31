#!/usr/bin/env python3
# H.264 硬件诊断: 写输入帧 -> 回读输入缓冲比对 -> 编码 -> 读 rinc 计数 + 字节数
#   诊断输入是否完整到达 + 编码器是否请求了正确的输入次数 (仿真 rinc=1176)
import sys, os, mmap, struct, time
sys.path.insert(0, os.path.dirname(__file__)); import h264_encode as he
CTRL,STATUS,QP,FLAGS,XTOTAL,YTOTAL,BYTES,RINC,IDREG = 0x00,0x04,0x08,0x0C,0x10,0x14,0x18,0x1C,0x3C
IN_BASE, OUT_BASE = 0x10000, 0x20000
bdf=sys.argv[1]; W,H=96,64
d=he.Dev(bdf)
print("ID=0x%08x"%d.rd(IDREG))
Y,U,V=he.load_frame(None,W,H); words,MBX,MBY=he.tile(Y,U,V,W,H)
# 写输入
for i,w in enumerate(words): d.wr(IN_BASE+i*4, w)
# 回读比对
bad=0; first=[]
for i in range(len(words)):
    got=d.rd(IN_BASE+i*4)
    if got!=words[i]:
        bad+=1
        if len(first)<6: first.append((i,hex(got),hex(words[i])))
print("输入回读: %d/%d 不符"%(bad,len(words)))
for i,g,w in first: print("  word[%d] got=%s exp=%s"%(i,g,w))
# 编码
d.wr(QP,27); d.wr(FLAGS,2); d.wr(XTOTAL,MBX-1); d.wr(YTOTAL,MBY-1); d.wr(CTRL,1)
t0=time.time()
while time.time()-t0<5:
    st=d.rd(STATUS)
    if (st&2) and not(st&1): break
print("编码: STATUS=0x%08x bytes=%d rinc=%d (仿真 rinc=1176)"%(st, d.rd(BYTES), d.rd(RINC)))
