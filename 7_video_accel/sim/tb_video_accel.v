// 功能仿真: 通过 AXI-Lite 驱动 video_accel, 逐模式对照 Python 参考值。
`timescale 1ns/1ps
`default_nettype none
module tb;
    reg clk=0, rst=1;
    always #2 clk=~clk;

    reg  [17:0] awaddr, araddr; reg [31:0] wdata; reg [3:0] wstrb;
    reg  awvalid, wvalid, bready, arvalid, rready;
    wire awready, wready, bvalid, arready, rvalid;
    wire [31:0] rdata; wire [1:0] bresp, rresp;

    video_accel #(.DATA_WIDTH(32), .ADDR_WIDTH(18)) dut (
        .clk(clk), .rst(rst),
        .s_axil_awaddr(awaddr), .s_axil_awprot(3'd0), .s_axil_awvalid(awvalid), .s_axil_awready(awready),
        .s_axil_wdata(wdata), .s_axil_wstrb(wstrb), .s_axil_wvalid(wvalid), .s_axil_wready(wready),
        .s_axil_bresp(bresp), .s_axil_bvalid(bvalid), .s_axil_bready(bready),
        .s_axil_araddr(araddr), .s_axil_arprot(3'd0), .s_axil_arvalid(arvalid), .s_axil_arready(arready),
        .s_axil_rdata(rdata), .s_axil_rresp(rresp), .s_axil_rvalid(rvalid), .s_axil_rready(rready)
    );

    task axil_write(input [17:0] a, input [31:0] d);
    begin
        @(posedge clk); #1;
        awaddr=a; wdata=d; wstrb=4'hF; awvalid=1; wvalid=1; bready=1;
        @(posedge clk);
        while (!bvalid) @(posedge clk);
        #1; awvalid=0; wvalid=0;
        @(posedge clk); #1; bready=0;
    end endtask

    task axil_read(input [17:0] a, output [31:0] d);
    begin
        @(posedge clk); #1;
        araddr=a; arvalid=1; rready=1;
        @(posedge clk);
        while (!rvalid) @(posedge clk);
        d = rdata;
        #1; arvalid=0;
        @(posedge clk); #1; rready=0;
    end endtask

    integer errors=0, i;
    reg [31:0] pix [0:3];
    reg [31:0] got, st;

    // 对照单模式(4 像素), exp0..3 为期望
    task run_mode(input [31:0] mode, input [31:0] p0, input [31:0] p1,
                  input [31:0] e0, input [31:0] e1, input [31:0] e2, input [31:0] e3);
        reg [31:0] e [0:3];
    begin
        e[0]=e0; e[1]=e1; e[2]=e2; e[3]=e3;
        // 写输入像素
        for (i=0;i<4;i=i+1) axil_write(18'h10000 + i*4, pix[i]);
        axil_write(18'h08, mode);      // MODE
        axil_write(18'h0C, 32'd4);     // WIDTH
        axil_write(18'h10, 32'd1);     // HEIGHT
        axil_write(18'h14, 32'd4);     // COUNT
        axil_write(18'h18, p0);        // PARAM0
        axil_write(18'h1C, p1);        // PARAM1
        axil_write(18'h00, 32'd1);     // CTRL start
        // 等 done
        st=0;
        for (i=0;i<1000 && !(st[1]);i=i+1) axil_read(18'h04, st);
        // 读输出对照
        for (i=0;i<4;i=i+1) begin
            axil_read(18'h20000 + i*4, got);
            if (got !== e[i]) begin
                errors=errors+1;
                $display("  FAIL mode=%0d pix[%0d] in=%08x got=%08x exp=%08x", mode, i, pix[i], got, e[i]);
            end
        end
        $display("  mode %0d done (STATUS=%08x)", mode, st);
    end endtask

    initial begin
        awvalid=0; wvalid=0; bready=0; arvalid=0; rready=0; wstrb=0; awaddr=0; araddr=0; wdata=0;
        pix[0]=32'h00C86432; pix[1]=32'h00102030; pix[2]=32'h00FFFF00; pix[3]=32'h00007F80;
        repeat(10) @(posedge clk); #1; rst=0; repeat(4) @(posedge clk);

        // ID 检查
        axil_read(18'h3C, got);
        if (got !== 32'h56414343) begin errors=errors+1; $display("  FAIL ID=%08x (exp 56414343)", got); end
        else $display("  ID = VACC OK");

        //        mode  p0          p1     e0        e1        e2        e3
        run_mode( 0, 32'd0,        32'd0,  32'h00c86432,32'h00102030,32'h00ffff00,32'h00007f80);
        run_mode( 1, 32'd0,        32'd0,  32'h007c56b6,32'h001d8a76,32'h00e20094,32'h00589540);
        run_mode( 3, 32'd0,        32'd0,  32'h007c7c7c,32'h001d1d1d,32'h00e2e2e2,32'h00585858);
        run_mode( 4, 32'd0,        32'd0,  32'h00379bcd,32'h00efdfcf,32'h000000ff,32'h00ff807f);
        run_mode( 5, 32'h00808080, 32'h80, 32'h0024f2d9,32'h00c8d0d8,32'h003f3fc0,32'h00c0ff00);
        run_mode( 6, 32'h80,       32'd0,  32'h00000000,32'h00000000,32'h00ffffff,32'h00000000);
        run_mode( 2, 32'd0,        32'd0,  32'h005aff96,32'h00006b00,32'h004bffff,32'h00000100);
        run_mode( 7, 32'h0A,       32'h50, 32'h00ff8748,32'h001e3246,32'h00ffff0a,32'h000aa8aa);

        if (errors==0) $display("==> VIDEO_ACCEL SIM: ALL PASS");
        else           $display("==> VIDEO_ACCEL SIM: %0d ERRORS", errors);
        $finish;
    end

    initial begin #200000; $display("TIMEOUT"); $finish; end
endmodule
`default_nettype wire
