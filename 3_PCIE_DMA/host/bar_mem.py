#!/usr/bin/env python3
# 单次 BAR 读/写:  bar_mem.py <BDF> <offset> [value]
#   读:  sudo python3 bar_mem.py 0000:01:00.0 0x0
#   写:  sudo python3 bar_mem.py 0000:01:00.0 0x0 0xDEADBEEF
import sys, os, mmap, struct
bdf = sys.argv[1]; off = int(sys.argv[2], 0)
val = int(sys.argv[3], 0) if len(sys.argv) > 3 else None
path = "/sys/bus/pci/devices/%s/resource0" % bdf
size = os.path.getsize(path)
fd = os.open(path, os.O_RDWR | os.O_SYNC)
m = mmap.mmap(fd, size, prot=mmap.PROT_READ | mmap.PROT_WRITE)
if val is None:
    m.seek(off); print("[%s] +0x%x = 0x%08x" % (bdf, off, struct.unpack('<I', m.read(4))[0]))
else:
    m.seek(off); m.write(struct.pack('<I', val)); m.flush()
    print("[%s] +0x%x <- 0x%08x" % (bdf, off, val))
m.close(); os.close(fd)
