// =====================================================================
// xk264 存储原语的 FPGA 可综合替换库 (Intel Stratix 10 / Quartus)
//   语义严格照搬 xk264 lib/behave/mem 的原始行为(读条件也一致),只去掉内部三态输出。
//   ram/rf: 写=!cen&!wen, 读=!cen&wen; rf_2p A口只读=!cen; rom=!cen。
//   ★不要把读改成无条件 — 会改变存储语义, 编码器会算错/卡死。★
//   注意: 非 ANSI 端口声明依赖默认 nettype=wire, 本文件不设 `default_nettype none`。
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
        if (!cen_i &&  wen_i) data_r <= mem_array[addr_i];   // 读 (仅非写周期)
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

// ---- 单端口寄存器堆 ----
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

// ---- 单端口 ROM ----
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

`default_nettype wire
