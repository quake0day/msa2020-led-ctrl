#!/bin/bash
# 在 Ubuntu 主机上编译并加载 mqnic 驱动 (kernel 6.16/7.0 已移植)。
# 前提: 板卡已烧 qsfp_mqnic.sof 并在 PCIe 槽内, 主机已 rescan 到 1234:1001。
# 用法: bash build_load_mqnic.sh  (在 ~/corundum 目录旁运行, 假设源码在 ~/corundum)
set -e
CORUNDUM=${CORUNDUM:-~/corundum}

# 0) 工具链 (本机原本无 gcc/make)
command -v gcc >/dev/null || { sudo apt-get update && sudo apt-get install -y build-essential; }

# 1) 恢复 Windows 检出丢失的软链 (utils 依赖)
cd "$CORUNDUM/utils"
[ -L lib ] || { rm -f lib; ln -s ../lib lib; }
[ -L include ] || { rm -f include; ln -s ../include include; }
cd "$CORUNDUM/lib/mqnic"
[ -L mqnic_hw.h ] || { rm -f mqnic_hw.h; ln -s ../../modules/mqnic/mqnic_hw.h mqnic_hw.h; }
[ -L mqnic_ioctl.h ] || { rm -f mqnic_ioctl.h; ln -s ../../modules/mqnic/mqnic_ioctl.h mqnic_ioctl.h; }

# 2) 编译内核模块
cd "$CORUNDUM/modules/mqnic"
make
echo "built: $(ls -la mqnic.ko | awk '{print $5}') bytes"

# 3) 加载
for m in ptp i2c-algo-bit i2c-mux i2c-dev; do sudo modprobe $m 2>/dev/null || true; done
sudo rmmod mqnic 2>/dev/null || true
sudo insmod mqnic.ko
sleep 2
echo "=== probe ==="; sudo dmesg | grep mqnic | tail -30
echo "=== netdevs ==="; ip -br link | grep enp1s0 || true

# 4) 用户态工具 + 板卡信息
cd "$CORUNDUM/utils" && make mqnic-dump
sudo ./mqnic-dump -d /dev/mqnic0 | head -40
