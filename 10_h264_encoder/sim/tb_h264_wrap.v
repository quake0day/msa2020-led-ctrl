// 验证 h264_wrap: 走 AXI-Lite (模拟 PCIe BAR) 写帧/设寄存器/触发/读码流,
// 输出应与 tb_h264 直连仿真的 out.264 完全一致。
`timescale 1ns/1ps
`default_nettype none
module tb_h264_wrap;
    localparam MBX=6, MBY=4, NWORDS=MBX*MBY*96;
    reg clk=0, rst=1; always #5 clk=~clk;

    reg  [17:0] awaddr, araddr; reg [31:0] wdata; reg [3:0] wstrb;
    reg  awvalid, wvalid, bready, arvalid, rready;
    wire awready, wready, bvalid, arready, rvalid; wire [31:0] rdata; wire [1:0] bresp, rresp;

    h264_wrap dut (
        .clk(clk), .rst(rst),
        .s_axil_awaddr(awaddr), .s_axil_awprot(3'd0), .s_axil_awvalid(awvalid), .s_axil_awready(awready),
        .s_axil_wdata(wdata), .s_axil_wstrb(wstrb), .s_axil_wvalid(wvalid), .s_axil_wready(wready),
        .s_axil_bresp(bresp), .s_axil_bvalid(bvalid), .s_axil_bready(bready),
        .s_axil_araddr(araddr), .s_axil_arprot(3'd0), .s_axil_arvalid(arvalid), .s_axil_arready(arready),
        .s_axil_rdata(rdata), .s_axil_rresp(rresp), .s_axil_rvalid(rvalid), .s_axil_rready(rready)
    );

    task axil_write(input [17:0] a, input [31:0] d);
    begin
        @(posedge clk); #1; awaddr=a; wdata=d; wstrb=4'hF; awvalid=1; wvalid=1; bready=1;
        @(posedge clk); while(!bvalid) @(posedge clk);
        #1; awvalid=0; wvalid=0; @(posedge clk); #1; bready=0;
    end endtask
    task axil_read(input [17:0] a, output [31:0] d);
    begin
        @(posedge clk); #1; araddr=a; arvalid=1; rready=1;
        @(posedge clk); while(!rvalid) @(posedge clk);
        d=rdata; #1; arvalid=0; @(posedge clk); #1; rready=0;
    end endtask

    reg [31:0] pixel_ram [0:NWORDS-1];
    integer i, fout, nbytes; reg [31:0] st, w;

    initial begin
        $readmemh("input.dat", pixel_ram);
        awvalid=0; wvalid=0; bready=0; arvalid=0; rready=0; wstrb=0; awaddr=0; araddr=0; wdata=0;
        repeat(10) @(posedge clk); #1; rst=0; repeat(4) @(posedge clk);
        // ID 检查
        axil_read(18'h3C, w);
        if (w!==32'h48323634) $display("  FAIL ID=%08x", w); else $display("  ID = H264 OK");
        // 写输入帧 (word i -> 0x10000 + i*4)
        for (i=0;i<NWORDS;i=i+1) axil_write(18'h10000 + i*4, pixel_ram[i]);
        $display("  loaded %0d input words", NWORDS);
        // 配置
        axil_write(18'h08, 32'd27);       // QP
        axil_write(18'h0C, 32'd2);        // FLAGS: intra=1, mode=0
        axil_write(18'h10, MBX-1);        // XTOTAL
        axil_write(18'h14, MBY-1);        // YTOTAL
        // 触发
        axil_write(18'h00, 32'd1);
        // 等 done
        st=0;
        for (i=0;i<200000 && !st[1];i=i+1) axil_read(18'h04, st);
        axil_read(18'h18, w); nbytes=w;
        $display("  ENCODE DONE: STATUS=%08x, bytes=%0d", st, nbytes);
        // 读码流
        fout=$fopen("out_wrap.264","wb");
        for (i=0;i<nbytes;i=i+1) begin
            if (i[1:0]==0) axil_read(18'h20000 + (i>>2)*4, w);
            $fwrite(fout, "%c", w[ (i[1:0])*8 +: 8 ]);
        end
        $fclose(fout);
        $display("  wrote out_wrap.264 (%0d bytes)", nbytes);
        $finish;
    end
    initial begin #300000000; $display("*** TIMEOUT ***"); $finish; end
endmodule
`default_nettype wire
