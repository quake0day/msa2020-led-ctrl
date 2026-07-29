#!/usr/bin/env python3
# 生成 8x8 2-D DCT/IDCT 的定点系数 (Q13, scale=8192) —— 同一张表同时供:
#   - RTL: 打印 Verilog initial 块 (dct_coef.vh)
#   - 主机参考模型: import 后用整数运算做位精确对照
# 正交归一 DCT-II 矩阵 C[k][n] = round(8192 * s(k) * cos((2n+1)k*pi/16))
#   s(0)=sqrt(1/8), s(k>=1)=sqrt(2/8)=0.5
# 2-D 正变换  F = C · X · C^T ; 反变换 X = C^T · F · C  (C 正交)
# 定点位移: 行变换后 >>S1, 列变换后 >>S2, S1+S2 = 26 (=2*13, 去掉两次 8192)
import math

SCALE_BITS = 13
S1 = 8
S2 = 18   # S1+S2 = 26

def build_C():
    C = [[0]*8 for _ in range(8)]
    for k in range(8):
        s = math.sqrt(1.0/8.0) if k == 0 else math.sqrt(2.0/8.0)
        for n in range(8):
            C[k][n] = int(round((1 << SCALE_BITS) * s * math.cos((2*n+1)*k*math.pi/16.0)))
    return C

C = build_C()

def _rshift_round(v, s):
    # 对称四舍五入右移 (与 RTL 一致): (v + (1<<(s-1))) >>> s  (算术)
    if s == 0: return v
    return (v + (1 << (s-1))) >> s   # Python >> 对负数是向下取整, 与 Verilog >>> 一致

def fdct_block(x):
    # x: 8x8 整数 (像素, 可选电平位移 -128). 返回 8x8 系数
    # 行: T[k][j] = sum_n C[k][n]*x[n][j]  >>S1
    T = [[0]*8 for _ in range(8)]
    for k in range(8):
        for j in range(8):
            acc = sum(C[k][n]*x[n][j] for n in range(8))
            T[k][j] = _rshift_round(acc, S1)
    # 列: F[k][l] = sum_j T[k][j]*C[l][j]  >>S2
    F = [[0]*8 for _ in range(8)]
    for k in range(8):
        for l in range(8):
            acc = sum(T[k][j]*C[l][j] for j in range(8))
            F[k][l] = _rshift_round(acc, S2)
    return F

def idct_block(f):
    # 反变换 X = C^T · F · C.  行: T[k][j]=sum_n C[n][k]*f[n][j] >>S1
    T = [[0]*8 for _ in range(8)]
    for k in range(8):
        for j in range(8):
            acc = sum(C[n][k]*f[n][j] for n in range(8))
            T[k][j] = _rshift_round(acc, S1)
    X = [[0]*8 for _ in range(8)]
    for k in range(8):
        for l in range(8):
            acc = sum(T[k][j]*C[j][l] for j in range(8))
            X[k][l] = _rshift_round(acc, S2)
    return X

def emit_verilog(path):
    with open(path, "w") as fp:
        fp.write("// 自动生成 (gen_dct.py) —— 8x8 DCT 系数 Q%d, S1=%d S2=%d\n" % (SCALE_BITS,S1,S2))
        fp.write("// C[k*8+n], 有符号\n")
        for k in range(8):
            for n in range(8):
                fp.write("    C[%2d] = 16'sd%d;\n" % (k*8+n, C[k][n]) if C[k][n]>=0
                         else "    C[%2d] = -16'sd%d;\n" % (k*8+n, -C[k][n]))
    print("wrote", path)

if __name__ == "__main__":
    print("C matrix (Q13):")
    for k in range(8):
        print(" ", C[k])
    # 自检: FDCT 后 IDCT 应近似还原
    import random
    x = [[ (k*8+n) % 256 - 128 for n in range(8)] for k in range(8)]
    F = fdct_block(x); X = idct_block(F)
    err = max(abs(x[k][n]-X[k][n]) for k in range(8) for n in range(8))
    print("round-trip max abs err (level-shifted):", err)
    emit_verilog("dct_coef.vh")
