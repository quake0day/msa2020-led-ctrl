// 验证 axil_cdc + h264_wrap 双时钟: s侧(快, 模拟pcie_clk) 驱 AXI, m侧(慢, enc_clk) 跑编码器。
// 输出应仍与 out.264 一致 (证明 CDC 正确)。
`timescale 1ns/1ps
`default_nettype none
module tb_h264_cdc;
    localparam MBX=6, MBY=4, NWORDS=MBX*MBY*96;
    reg sclk=0, mclk=0, rst=1;
    always #5 sclk=~sclk;     // 快时钟
    always #17 mclk=~mclk;    // 慢时钟 (异步, ~非整数比)

    reg  [17:0] awaddr, araddr; reg [31:0] wdata; reg [3:0] wstrb;
    reg  awvalid, wvalid, bready, arvalid, rready;
    wire awready, wready, bvalid, arready, rvalid; wire [31:0] rdata; wire [1:0] bresp, rresp;
    // cdc <-> wrap
    wire [17:0] e_aw,e_ar; wire [2:0] e_awp,e_arp;
    wire e_awv,e_awr,e_wv,e_wr,e_bv,e_br,e_arv,e_arr,e_rv,e_rr;
    wire [31:0] e_wd,e_rd; wire [3:0] e_ws; wire [1:0] e_bresp,e_rresp;

    axil_cdc #(.ADDR_WIDTH(18),.DATA_WIDTH(32)) cdc (
        .s_clk(sclk),.s_rst(rst),
        .s_awaddr(awaddr),.s_awprot(3'd0),.s_awvalid(awvalid),.s_awready(awready),
        .s_wdata(wdata),.s_wstrb(wstrb),.s_wvalid(wvalid),.s_wready(wready),
        .s_bresp(bresp),.s_bvalid(bvalid),.s_bready(bready),
        .s_araddr(araddr),.s_arprot(3'd0),.s_arvalid(arvalid),.s_arready(arready),
        .s_rdata(rdata),.s_rresp(rresp),.s_rvalid(rvalid),.s_rready(rready),
        .m_clk(mclk),.m_rst(rst),
        .m_awaddr(e_aw),.m_awprot(e_awp),.m_awvalid(e_awv),.m_awready(e_awr),
        .m_wdata(e_wd),.m_wstrb(e_ws),.m_wvalid(e_wv),.m_wready(e_wr),
        .m_bresp(e_bresp),.m_bvalid(e_bv),.m_bready(e_br),
        .m_araddr(e_ar),.m_arprot(e_arp),.m_arvalid(e_arv),.m_arready(e_arr),
        .m_rdata(e_rd),.m_rresp(e_rresp),.m_rvalid(e_rv),.m_rready(e_rr)
    );
    h264_wrap dut (
        .clk(mclk), .rst(rst),
        .s_axil_awaddr(e_aw),.s_axil_awprot(e_awp),.s_axil_awvalid(e_awv),.s_axil_awready(e_awr),
        .s_axil_wdata(e_wd),.s_axil_wstrb(e_ws),.s_axil_wvalid(e_wv),.s_axil_wready(e_wr),
        .s_axil_bresp(e_bresp),.s_axil_bvalid(e_bv),.s_axil_bready(e_br),
        .s_axil_araddr(e_ar),.s_axil_arprot(e_arp),.s_axil_arvalid(e_arv),.s_axil_arready(e_arr),
        .s_axil_rdata(e_rd),.s_axil_rresp(e_rresp),.s_axil_rvalid(e_rv),.s_axil_rready(e_rr)
    );

    task axil_write(input [17:0] a, input [31:0] d);
    begin
        @(posedge sclk); #1; awaddr=a; wdata=d; wstrb=4'hF; awvalid=1; wvalid=1; bready=1;
        @(posedge sclk); while(!bvalid) @(posedge sclk);
        #1; awvalid=0; wvalid=0; @(posedge sclk); #1; bready=0;
    end endtask
    task axil_read(input [17:0] a, output [31:0] d);
    begin
        @(posedge sclk); #1; araddr=a; arvalid=1; rready=1;
        @(posedge sclk); while(!rvalid) @(posedge sclk);
        d=rdata; #1; arvalid=0; @(posedge sclk); #1; rready=0;
    end endtask

    reg [31:0] pram [0:NWORDS-1]; integer i,fout,nb; reg [31:0] st,w;
    initial begin
        $readmemh("input.dat", pram);
        awvalid=0;wvalid=0;bready=0;arvalid=0;rready=0;wstrb=0;awaddr=0;araddr=0;wdata=0;
        repeat(10) @(posedge sclk); #1; rst=0; repeat(6) @(posedge sclk);
        axil_read(18'h3C,w); if (w===32'h48323634) $display("  ID=H264 OK"); else $display("  FAIL ID=%08x",w);
        for (i=0;i<NWORDS;i=i+1) axil_write(18'h10000+i*4, pram[i]);
        axil_write(18'h08,32'd27); axil_write(18'h0C,32'd2); axil_write(18'h10,MBX-1); axil_write(18'h14,MBY-1);
        axil_write(18'h00,32'd1);
        st=0; for (i=0;i<400000 && !st[1];i=i+1) axil_read(18'h04,st);
        axil_read(18'h18,w); nb=w; $display("  DONE STATUS=%08x bytes=%0d",st,nb);
        fout=$fopen("out_cdc.264","wb");
        for (i=0;i<nb;i=i+1) begin if(i[1:0]==0) axil_read(18'h20000+(i>>2)*4,w); $fwrite(fout,"%c",w[(i[1:0])*8+:8]); end
        $fclose(fout); $display("  wrote out_cdc.264 (%0d bytes)",nb); $finish;
    end
    initial begin #500000000; $display("*** TIMEOUT ***"); $finish; end
endmodule
`default_nettype wire
