#!/bin/bash
# 修复 MSA-2020 (1234:1002) 上游桥 00:01.0 的可预取窗口。
# remove+rescan 后, 该桥的 prefetchable window 会被置成 base>limit(禁用) 且 upper32=0,
# 导致所有 MemRd/MemWr 无法转发到 FPGA(读全 0xffffffff, 无任何 AER 错误)。
# 本脚本把窗口重设为覆盖 BAR0 所在的 0x40_17100000..171fffff, 并打开 Mem 译码。
set -e
DEV=$(lspci -d 1234:1002 | cut -d" " -f1)
[ -z "$DEV" ] && { echo "找不到 1234:1002 设备"; exit 1; }
BR=$(basename $(dirname $(readlink -f /sys/bus/pci/devices/0000:$DEV)))   # 上游桥 BDF
BR=${BR#0000:}
# 读回 BAR 高/低 32 位, 动态计算窗口(1MB 对齐)
B0=$(sudo setpci -s $DEV 0x10.l); B1=$(sudo setpci -s $DEV 0x14.l)
LO=$(( (0x$B0) & 0xFFF00000 )); HI=$(( 0x$B1 ))
BASE20=$(printf "%03x" $(( LO >> 20 )))
REG24=$(printf "%s1%s1" $BASE20 $BASE20)          # base/limit[31:20]=同一 1MB 块, 均置 64-bit-cap 位
printf "设备=%s 桥=%s BAR=0x%02x_%08x\n" $DEV $BR $HI $LO
sudo setpci -s $BR 0x28.l=$(printf "%08x" $HI)    # PREF_BASE_UPPER32
sudo setpci -s $BR 0x2c.l=$(printf "%08x" $HI)    # PREF_LIMIT_UPPER32
sudo setpci -s $BR 0x24.l=$REG24                  # PREF base/limit low
sudo setpci -s $BR   COMMAND=0x0006               # 桥 Mem 转发
sudo setpci -s $DEV  COMMAND=0x0006               # 设备 Mem+BusMaster
echo "桥窗口: 0x24=$(sudo setpci -s $BR 0x24.l) up=$(sudo setpci -s $BR 0x28.l)/$(sudo setpci -s $BR 0x2c.l)  -> 已修复"
