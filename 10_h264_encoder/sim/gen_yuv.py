#!/usr/bin/env python3
# 生成 xk264 输入: 一帧 YUV420 -> (1) 平面 ref.yuv 供 ffmpeg 比对
#                                 (2) MB-tiled input.dat (hex 32-bit 字) 供仿真 pixel_ram
# MB 光栅序; 每 MB = 64 luma 字(光栅,4px/字,首像素高字节) + 32 chroma 字
# (每 rdata 64-bit = U0 V0 U1 V1 U2 V2 U3 V3, 拆成 2 个 32-bit 字, U0 在高字节)
import sys

W, H = 96, 64          # 必须是 16 的倍数 (小帧 -> 仿真快)
MBX, MBY = W//16, H//16

def clamp(v): return 0 if v<0 else (255 if v>255 else int(v))

def make_frame():
    Y=[[0]*W for _ in range(H)]; U=[[128]*(W//2) for _ in range(H//2)]; V=[[128]*(W//2) for _ in range(H//2)]
    for y in range(H):
        for x in range(W):
            g = (x*255)//(W-1)                       # 水平渐变
            box = 200 if (W//4<=x<3*W//4 and H//4<=y<3*H//4) else 0  # 中间亮框
            Y[y][x] = clamp(g//2 + box//2 + 20)
    for y in range(H//2):
        for x in range(W//2):
            U[y][x] = clamp(128 + (x-W//4)*2)        # 轻微色度渐变
            V[y][x] = clamp(128 + (y-H//4)*2)
    return Y,U,V

def w32(p0,p1,p2,p3): return (p0<<24)|(p1<<16)|(p2<<8)|p3   # p0 高字节

def main():
    Y,U,V = make_frame()
    # (1) 平面 YUV420 (Y 全, 然后 U, 然后 V)
    with open("ref.yuv","wb") as f:
        for row in Y: f.write(bytes(row))
        for row in U: f.write(bytes(row))
        for row in V: f.write(bytes(row))
    # (2) MB-tiled hex
    words=[]
    for mby in range(MBY):
        for mbx in range(MBX):
            # luma 16x16 光栅, 4px/字
            for r in range(16):
                for c in range(0,16,4):
                    p=[Y[mby*16+r][mbx*16+c+i] for i in range(4)]
                    words.append(w32(*p))
            # chroma: addr_uv 0..15 -> 每个出 2 个 32-bit 字
            #   addr_uv*4+k (k=0..3) = 8x8 光栅索引; 高字 {U0,V0,U1,V1} 低字 {U2,V2,U3,V3}
            for auv in range(16):
                us=[]; vs=[]
                for k in range(4):
                    idx=auv*4+k; rr=idx//8; cc=idx%8
                    us.append(U[mby*8+rr][mbx*8+cc]); vs.append(V[mby*8+rr][mbx*8+cc])
                words.append(w32(us[0],vs[0],us[1],vs[1]))   # 高字
                words.append(w32(us[2],vs[2],us[3],vs[3]))   # 低字
    with open("input.dat","w") as f:
        for w in words: f.write("%08x\n"%w)
    print("W=%d H=%d  MBX=%d MBY=%d  MBs=%d  pixel_ram words=%d (=%d/MB)"
          %(W,H,MBX,MBY,MBX*MBY,len(words),len(words)//(MBX*MBY)))
    print("wrote ref.yuv (%d bytes) + input.dat"%(W*H*3//2))

if __name__=="__main__": main()
