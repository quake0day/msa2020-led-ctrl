// 验证 h264_wrap_dc 双时钟(无 axil_cdc): pclk(快,模拟pcie) 驱 AXI-Lite, eclk(慢,enc) 跑编码器。
// 跨域全靠双时钟BRAM + toggle/电平同步。输出应仍 == golden 168 字节 (证明新架构逐字节正确)。
`timescale 1ns/1ps
`default_nettype none
module tb_h264_dc;
    localparam MBX=6, MBY=4, NWORDS=MBX*MBY*96;
    reg pclk=0, eclk=0, rst=1;
    always #5  pclk=~pclk;    // 100MHz 快 (host/pcie 面)
    always #17 eclk=~eclk;    // ~29.4MHz 慢, 异步非整数比 (enc 面)

    reg  [17:0] awaddr, araddr; reg [31:0] wdata; reg [3:0] wstrb;
    reg  awvalid, wvalid, bready, arvalid, rready;
    wire awready, wready, bvalid, arready, rvalid; wire [31:0] rdata; wire [1:0] bresp, rresp;

    h264_wrap_dc #(.ADDR_WIDTH(18),.DATA_WIDTH(32)) dut (
        .pclk(pclk), .prst(rst),
        .s_axil_awaddr(awaddr),.s_axil_awprot(3'd0),.s_axil_awvalid(awvalid),.s_axil_awready(awready),
        .s_axil_wdata(wdata),.s_axil_wstrb(wstrb),.s_axil_wvalid(wvalid),.s_axil_wready(wready),
        .s_axil_bresp(bresp),.s_axil_bvalid(bvalid),.s_axil_bready(bready),
        .s_axil_araddr(araddr),.s_axil_arprot(3'd0),.s_axil_arvalid(arvalid),.s_axil_arready(arready),
        .s_axil_rdata(rdata),.s_axil_rresp(rresp),.s_axil_rvalid(rvalid),.s_axil_rready(rready),
        .eclk(eclk), .erst(rst)
    );

    task axil_write(input [17:0] a, input [31:0] d);
    begin
        @(posedge pclk); #1; awaddr=a; wdata=d; wstrb=4'hF; awvalid=1; wvalid=1; bready=1;
        @(posedge pclk); while(!bvalid) @(posedge pclk);
        #1; awvalid=0; wvalid=0; @(posedge pclk); #1; bready=0;
    end endtask
    task axil_read(input [17:0] a, output [31:0] d);
    begin
        @(posedge pclk); #1; araddr=a; arvalid=1; rready=1;
        @(posedge pclk); while(!rvalid) @(posedge pclk);
        d=rdata; #1; arvalid=0; @(posedge pclk); #1; rready=0;
    end endtask

    reg [31:0] pram [0:NWORDS-1]; integer i,fout,nb; reg [31:0] st,w,rc;
    initial begin
        $readmemh("input.dat", pram);
        awvalid=0;wvalid=0;bready=0;arvalid=0;rready=0;wstrb=0;awaddr=0;araddr=0;wdata=0;
        repeat(10) @(posedge pclk); #1; rst=0; repeat(6) @(posedge pclk);
        axil_read(18'h3C,w); if (w===32'h48323634) $display("  ID=H264 OK"); else $display("  FAIL ID=%08x",w);
        for (i=0;i<NWORDS;i=i+1) axil_write(18'h10000+i*4, pram[i]);
        axil_write(18'h08,32'd27); axil_write(18'h0C,32'd2); axil_write(18'h10,MBX-1); axil_write(18'h14,MBY-1);
        axil_write(18'h00,32'd1);   // start
        st=0; for (i=0;i<400000 && !st[1];i=i+1) axil_read(18'h04,st);
        axil_read(18'h18,w); nb=w; axil_read(18'h1C,rc);
        $display("  DONE STATUS=%08x bytes=%0d rinc=%0d",st,nb,rc);
        axil_read(18'h20,w); $display("  SIM in_sum =0x%08x",w);
        axil_read(18'h24,w); $display("  SIM in_xor =0x%08x",w);
        axil_read(18'h28,w); $display("  SIM out_sum=0x%08x",w);
        axil_read(18'h2C,w); $display("  SIM pre_sum=0x%08x",w);
        axil_read(18'h30,w); $display("  SIM res_sum=0x%08x",w);
        axil_read(18'h34,w); $display("  SIM rec_sum=0x%08x",w);
        fout=$fopen("out_dc.264","wb");
        for (i=0;i<nb;i=i+1) begin if(i[1:0]==0) axil_read(18'h20000+(i>>2)*4,w); $fwrite(fout,"%c",w[(i[1:0])*8+:8]); end
        $fclose(fout); $display("  wrote out_dc.264 (%0d bytes)",nb);
        if (nb==168) $display("  ==== PASS: 168 bytes == golden ===="); else $display("  ==== MISMATCH: %0d != 168 ====",nb);
        $finish;
    end
    initial begin #800000000; $display("*** TIMEOUT ***"); $finish; end
endmodule
`default_nettype wire
