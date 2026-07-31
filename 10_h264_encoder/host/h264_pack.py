#!/usr/bin/env python3
# =====================================================================
# H.264 码流打包器: xk264 硬件只输出 CAVLC slice-data (top.v 里 sh_we 接 0,
# 不产 SPS/PPS/slice-header/起始码)。本工具在软件侧生成 SPS+PPS+slice-header,
# 位级拼接硬件的 slice-data, 加 RBSP trailing + 防竞争字节 + Annex-B 起始码,
# 产出可被 ffmpeg 解码的 .264。这是 H.264 硬件编码器的标准软硬件分工。
#
#   用法: python3 h264_pack.py <enc_slice.bin> <out.264> <MBX> <MBY> <QP>
# =====================================================================
import sys

class BW:
    def __init__(self): self.bits=[]
    def u(self,val,n):
        for i in range(n-1,-1,-1): self.bits.append((val>>i)&1)
    def ue(self,val):
        v=val+1; n=v.bit_length()
        self.u(0, n-1); self.u(v, n)      # (n-1) 前导零 + v 的 n bit
    def se(self,val):
        self.ue(2*val-1 if val>0 else -2*val)
    def align_rbsp(self):                  # rbsp_trailing_bits: 停止位 1 + 补零到字节
        self.bits.append(1)
        while len(self.bits)%8: self.bits.append(0)
    def bytes(self):
        assert len(self.bits)%8==0
        out=bytearray()
        for i in range(0,len(self.bits),8):
            b=0
            for k in range(8): b=(b<<1)|self.bits[i+k]
            out.append(b)
        return bytes(out)

def bits_of(data):                          # 字节流 -> bit 列表 (MSB first)
    out=[]
    for by in data:
        for i in range(7,-1,-1): out.append((by>>i)&1)
    return out

def last_set_bit_index(data):               # 最后一个 1 的位置 (= slice_data 位数)
    bs=bits_of(data)
    for i in range(len(bs)-1,-1,-1):
        if bs[i]: return i                  # 该位是 rbsp 停止位, 之前是 slice_data
    return 0

def emulation_prevent(rbsp):                # 00 00 00/01/02/03 -> 插 03
    out=bytearray(); zeros=0
    for b in rbsp:
        if zeros>=2 and b<=3:
            out.append(3); zeros=0
        out.append(b)
        zeros = zeros+1 if b==0 else 0
    return bytes(out)

def nal(nal_hdr, rbsp_bytes):
    return b'\x00\x00\x00\x01' + bytes([nal_hdr]) + emulation_prevent(rbsp_bytes)

def make_sps(mbx, mby, level=30):
    w=BW()
    w.u(66,8)          # profile_idc = Baseline
    w.u(0,8)           # constraint flags + reserved
    w.u(level,8)       # level_idc
    w.ue(0)            # sps_id
    w.ue(0)            # log2_max_frame_num_minus4  -> max_frame_num=16
    w.ue(0)            # pic_order_cnt_type=0
    w.ue(0)            # log2_max_poc_lsb_minus4    -> max_poc_lsb=16
    w.ue(1)            # max_num_ref_frames
    w.u(0,1)           # gaps_in_frame_num_allowed
    w.ue(mbx-1)        # pic_width_in_mbs_minus1
    w.ue(mby-1)        # pic_height_in_map_units_minus1
    w.u(1,1)           # frame_mbs_only_flag
    w.u(1,1)           # direct_8x8_inference_flag
    w.u(0,1)           # frame_cropping_flag
    w.u(0,1)           # vui_parameters_present_flag
    w.align_rbsp()
    return w.bytes()

def make_pps(qp):
    w=BW()
    w.ue(0)            # pps_id
    w.ue(0)            # sps_id
    w.u(0,1)           # entropy_coding_mode_flag = CAVLC
    w.u(0,1)           # bottom_field_pic_order_present
    w.ue(0)            # num_slice_groups_minus1
    w.ue(0)            # num_ref_idx_l0_default_active_minus1
    w.ue(0)            # num_ref_idx_l1_default_active_minus1
    w.u(0,1)           # weighted_pred_flag
    w.u(0,2)           # weighted_bipred_idc
    w.se(qp-26)        # pic_init_qp_minus26  -> pic_init_qp = qp
    w.se(0)            # pic_init_qs_minus26
    w.se(0)            # chroma_qp_index_offset
    w.u(0,1)           # deblocking_filter_control_present_flag
    w.u(0,1)           # constrained_intra_pred_flag
    w.u(0,1)           # redundant_pic_cnt_present_flag
    w.align_rbsp()
    return w.bytes()

def make_idr_slice(qp, slice_data_bits):
    w=BW()
    w.ue(0)            # first_mb_in_slice
    w.ue(7)            # slice_type = I (all-I)
    w.ue(0)            # pps_id
    w.u(0,4)           # frame_num (log2_max_frame_num=4)
    w.ue(0)            # idr_pic_id
    w.u(0,4)           # pic_order_cnt_lsb (log2=4)
    # dec_ref_pic_marking (IDR)
    w.u(0,1)           # no_output_of_prior_pics_flag
    w.u(0,1)           # long_term_reference_flag
    w.se(0)            # slice_qp_delta (pic_init_qp=qp -> 0)
    # slice_data(): 位级追加硬件 slice_data
    w.bits += slice_data_bits
    w.align_rbsp()
    return w.bytes()

def main():
    enc, out, mbx, mby, qp = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
    E = open(enc,"rb").read()
    S = last_set_bit_index(E)               # slice_data 位数
    sdbits = bits_of(E)[:S]
    sps = nal(0x67, make_sps(mbx,mby))
    pps = nal(0x68, make_pps(qp))
    slc = nal(0x65, make_idr_slice(qp, sdbits))   # IDR slice NAL header 0x65
    open(out,"wb").write(sps+pps+slc)
    print("packed: %d slice-data bits, .264 = %d bytes (SPS %d + PPS %d + slice %d)"
          %(S, len(sps)+len(pps)+len(slc), len(sps), len(pps), len(slc)))

if __name__=="__main__": main()
