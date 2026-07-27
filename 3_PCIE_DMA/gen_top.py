#!/usr/bin/env python3
# 从 ip/pcie/synth/pcie.v 的端口表生成顶层 rtl/pcie_dma.v:
#   - rxm_bar0(32b Avalon-MM 主) -> 256KB 片内 RAM(推断)
#   - rx_in/tx_out -> PCIe 引脚; refclk/perst/npor/ninit_done 接好
#   - 所有 pipe/sim 输入按 project5 方式置 0; 未用输出悬空
import re, sys

src = open('ip/pcie/synth/pcie.v', encoding='utf-8', errors='ignore').read()
m = re.search(r'module\s+pcie\s*\((.*?)\);', src, re.S)
body = m.group(1)
ports = []
for line in body.splitlines():
    line = re.sub(r'//.*', '', line).strip().rstrip(',').strip()
    mm = re.match(r'(input|output)\s+wire\s*(\[[0-9:]+\])?\s*([A-Za-z_][A-Za-z_0-9]*)$', line)
    if mm:
        d, w, name = mm.group(1), mm.group(2), mm.group(3)
        width = 1
        if w:
            hi = int(w.strip('[]').split(':')[0]); width = hi + 1
        ports.append((d, width, name))

def tie0(w):
    return "1'b0" if w == 1 else "%d'd0" % w

conns = []
for d, w, name in ports:
    if name == 'refclk':                 c = 'pcie_refclk'
    elif name == 'npor':                 c = "1'b1"
    elif name == 'pin_perst':            c = 'pcie_perstn'
    elif name == 'ninit_done':           c = 'ninit_done'
    elif name == 'coreclkout_hip':       c = 'coreclk'
    elif name == 'app_nreset_status':    c = 'app_nreset'
    elif name == 'rxm_bar0_address_o':      c = 'rxm_address'
    elif name == 'rxm_bar0_byteenable_o':   c = 'rxm_byteenable'
    elif name == 'rxm_bar0_read_o':         c = 'rxm_read'
    elif name == 'rxm_bar0_write_o':        c = 'rxm_write'
    elif name == 'rxm_bar0_writedata_o':    c = 'rxm_writedata'
    elif name == 'rxm_bar0_readdata_i':     c = 'rxm_readdata'
    elif name == 'rxm_bar0_readdatavalid_i':c = 'rxm_readdatavalid'
    elif name == 'rxm_bar0_waitrequest_i':  c = "1'b0"
    else:
        mr = re.match(r'rx_in(\d+)$', name)
        mt = re.match(r'tx_out(\d+)$', name)
        if mr:   c = 'pcie_rx[%s]' % mr.group(1)
        elif mt: c = 'pcie_tx[%s]' % mt.group(1)
        elif d == 'input':  c = tie0(w)   # pipe/sim/cra/irq 等输入全部置 0
        else:               c = ''         # 未用输出悬空
    conns.append('        .%-26s (%s)' % (name, c))

inst = 'pcie pcie_hip_inst (\n' + ',\n'.join(conns) + '\n    );'

top = '''// =====================================================================
// MSA-2020 独立 PCIe 最小实验 (Gen3x8, Avalon-MM) —— 由 gen_top.py 生成
//   主机 mmap(BAR0) -> PCIe 硬核 rxm_bar0(32b) -> 256KB 片内 RAM。
//   PCIe 硬核用独立 IP ip/pcie.ip; pipe/sim 端口按硬件模式全部置 0(参 5 fpga.v)。
//   LED(绿, 低有效): grn[0]=pcie_perstn(主机在); grn[1]=coreclk 心跳(硬核在跑)
// =====================================================================
`default_nettype none
module pcie_dma (
    input  wire        pcie_refclk,   // 100MHz HCSL (AM34)
    input  wire        pcie_perstn,   // PERST# (AC26)
    input  wire [7:0]  pcie_rx,
    output wire [7:0]  pcie_tx,
    output wire [1:0]  led_user_grn
);
    wire        coreclk;              // coreclkout_hip (Gen3x8 = 250MHz)
    wire        app_nreset;           // 应用层复位状态
    wire        ninit_done;

    // ---- rxm_bar0 (32-bit Avalon-MM 主) ----
    wire [63:0] rxm_address;
    wire [3:0]  rxm_byteenable;
    wire        rxm_read, rxm_write;
    wire [31:0] rxm_writedata;
    reg  [31:0] rxm_readdata;
    reg         rxm_readdatavalid;

    // ---- 256KB 片内 RAM (64K x 32-bit), BAR0 窗口, 1 拍读延迟 ----
    reg [31:0] mem [0:65535];
    wire [15:0] word_addr = rxm_address[17:2];
    always @(posedge coreclk) begin
        if (rxm_write) begin
            if (rxm_byteenable[0]) mem[word_addr][7:0]   <= rxm_writedata[7:0];
            if (rxm_byteenable[1]) mem[word_addr][15:8]  <= rxm_writedata[15:8];
            if (rxm_byteenable[2]) mem[word_addr][23:16] <= rxm_writedata[23:16];
            if (rxm_byteenable[3]) mem[word_addr][31:24] <= rxm_writedata[31:24];
        end
        rxm_readdata      <= mem[word_addr];
        rxm_readdatavalid <= rxm_read;
    end

    // ---- 状态 LED ----
    reg [26:0] hb = 27'd0;
    always @(posedge coreclk) hb <= hb + 27'd1;
    assign led_user_grn[0] = ~pcie_perstn;   // 亮 = 主机已释放 PERST#
    assign led_user_grn[1] = ~hb[26];        // 闪 = coreclk 心跳

    // ---- S10 复位释放 -> ninit_done ----
    reset_release reset_release_inst (
        .ninit_done (ninit_done)
    );

    // ---- PCIe 硬核 (Avalon-MM 桥) ----
    ''' + inst + '''
endmodule
`default_nettype wire
'''
open('rtl/pcie_dma.v', 'w', encoding='utf-8').write(top)
print("wrote rtl/pcie_dma.v ; %d ports wired" % len(ports))
# sanity: report unconnected-output + tie0-input counts
ti = sum(1 for d,w,n in ports if d=='input')
to = sum(1 for d,w,n in ports if d=='output')
print("inputs=%d outputs=%d" % (ti, to))
