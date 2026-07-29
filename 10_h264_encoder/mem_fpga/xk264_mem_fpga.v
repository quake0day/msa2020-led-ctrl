// =====================================================================
// xk264 存储原语的 FPGA 可综合替换库 (Intel Stratix 10 / Quartus)
//   替换 lib/behave/mem/ 里的 ASIC 行为模型:去掉内部三态输出(FPGA 无内部三态),
//   改成标准可推断 M20K 模板。端口/参数/模块名与原库完全一致 → 直接替换,不改原文件。
//   (原库 cen/oen/wen 均低有效;oen 仅门控输出,FPGA 恒驱动寄存输出即可,读方本就只在读时采样。)
//   注意: 非 ANSI 端口声明依赖默认 nettype=wire, 故本文件不设 `default_nettype none`。
// =====================================================================

// ---- 单端口 RAM ----
module ram_1p (clk, cen_i, oen_i, wen_i, addr_i, data_i, data_o);
    parameter Word_Width = 32;
    parameter Addr_Width = 8;
    input                    clk, cen_i, oen_i, wen_i;
    input  [Addr_Width-1:0]  addr_i;
    input  [Word_Width-1:0]  data_i;
    output [Word_Width-1:0]  data_o;
    (* ramstyle = "M20K" *) reg [Word_Width-1:0] mem_array[(1<<Addr_Width)-1:0];
    reg [Word_Width-1:0] data_r;
    always @(posedge clk) begin
        if (!cen_i && !wen_i) mem_array[addr_i] <= data_i;   // 写
        if (!cen_i &&  wen_i) data_r <= mem_array[addr_i];   // 读(寄存)
    end
    assign data_o = data_r;
endmodule

// ---- 双端口 RAM (两端口各自可读写, 独立时钟) ----
module ram_2p (clka, cena_i, oena_i, wena_i, addra_i, dataa_o, dataa_i,
               clkb, cenb_i, oenb_i, wenb_i, addrb_i, datab_o, datab_i);
    parameter Word_Width = 32;
    parameter Addr_Width = 8;
    input                    clka, cena_i, oena_i, wena_i;
    input  [Addr_Width-1:0]  addra_i;
    input  [Word_Width-1:0]  dataa_i;
    output [Word_Width-1:0]  dataa_o;
    input                    clkb, cenb_i, oenb_i, wenb_i;
    input  [Addr_Width-1:0]  addrb_i;
    input  [Word_Width-1:0]  datab_i;
    output [Word_Width-1:0]  datab_o;
    (* ramstyle = "M20K" *) reg [Word_Width-1:0] mem_array[(1<<Addr_Width)-1:0];
    reg [Word_Width-1:0] dataa_r, datab_r;
    always @(posedge clka) begin
        if (!cena_i && !wena_i) mem_array[addra_i] <= dataa_i;
        if (!cena_i &&  wena_i) dataa_r <= mem_array[addra_i];
    end
    always @(posedge clkb) begin
        if (!cenb_i && !wenb_i) mem_array[addrb_i] <= datab_i;
        if (!cenb_i &&  wenb_i) datab_r <= mem_array[addrb_i];
    end
    assign dataa_o = dataa_r;
    assign datab_o = datab_r;
endmodule

// ---- 单端口寄存器堆 (wen 低有效: 写; 否则读) ----
module rf_1p (clk, cen_i, wen_i, addr_i, data_i, data_o);
    parameter Word_Width = 32;
    parameter Addr_Width = 8;
    input                    clk, cen_i, wen_i;
    input  [Addr_Width-1:0]  addr_i;
    input  [Word_Width-1:0]  data_i;
    output [Word_Width-1:0]  data_o;
    (* ramstyle = "MLAB" *) reg [Word_Width-1:0] mem_array[(1<<Addr_Width)-1:0];
    reg [Word_Width-1:0] data_r;
    always @(posedge clk) begin
        if (!cen_i && !wen_i) mem_array[addr_i] <= data_i;
        if (!cen_i &&  wen_i) data_r <= mem_array[addr_i];
    end
    assign data_o = data_r;
endmodule

// ---- 双端口寄存器堆 (A 口只读, B 口只写) ----
module rf_2p (clka, cena_i, addra_i, dataa_o, clkb, cenb_i, wenb_i, addrb_i, datab_i);
    parameter Word_Width = 32;
    parameter Addr_Width = 8;
    input                    clka, cena_i;
    input  [Addr_Width-1:0]  addra_i;
    output [Word_Width-1:0]  dataa_o;
    input                    clkb, cenb_i, wenb_i;
    input  [Addr_Width-1:0]  addrb_i;
    input  [Word_Width-1:0]  datab_i;
    (* ramstyle = "MLAB" *) reg [Word_Width-1:0] mem_array[(1<<Addr_Width)-1:0];
    reg [Word_Width-1:0] dataa_r;
    always @(posedge clka) if (!cena_i) dataa_r <= mem_array[addra_i];
    assign dataa_o = dataa_r;
    always @(posedge clkb) if (!cenb_i && !wenb_i) mem_array[addrb_i] <= datab_i;
endmodule

// ---- 单端口 ROM (未初始化 -> 读为不定; 内容由使用处/初始化文件决定) ----
module rom_1p (clk, cen_i, oen_i, addr_i, data_o);
    parameter Word_Width = 32;
    parameter Addr_Width = 8;
    input                    clk, cen_i, oen_i;
    input  [Addr_Width-1:0]  addr_i;
    output [Word_Width-1:0]  data_o;
    (* ramstyle = "M20K" *) reg [Word_Width-1:0] mem_array[(1<<Addr_Width)-1:0];
    reg [Word_Width-1:0] data_r;
    always @(posedge clk) if (!cen_i) data_r <= mem_array[addr_i];
    assign data_o = data_r;
endmodule
