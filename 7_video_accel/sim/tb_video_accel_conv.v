// 功能仿真: video_accel 卷积模式(mode 8), 对照 Python ref_conv。
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
        @(posedge clk); #1; awaddr=a; wdata=d; wstrb=4'hF; awvalid=1; wvalid=1; bready=1;
        @(posedge clk); while (!bvalid) @(posedge clk);
        #1; awvalid=0; wvalid=0; @(posedge clk); #1; bready=0;
    end endtask
    task axil_read(input [17:0] a, output [31:0] d);
    begin
        @(posedge clk); #1; araddr=a; arvalid=1; rready=1;
        @(posedge clk); while (!rvalid) @(posedge clk);
        d = rdata; #1; arvalid=0; @(posedge clk); #1; rready=0;
    end endtask

    integer errors=0, i;
    reg [31:0] img [0:15];
    reg [31:0] eid [0:15];   // identity expected
    reg [31:0] ebl [0:15];   // blur expected
    reg [31:0] got, st;

    task load_img; begin
        for (i=0;i<16;i=i+1) axil_write(18'h10000 + i*4, img[i]);
    end endtask

    task run_conv(input [31:0] p0,p1,p2,p3);
    begin
        axil_write(18'h08, 32'd8);   // MODE=conv
        axil_write(18'h0C, 32'd4);   // WIDTH
        axil_write(18'h10, 32'd4);   // HEIGHT
        axil_write(18'h14, 32'd16);  // COUNT
        axil_write(18'h18, p0); axil_write(18'h1C, p1);
        axil_write(18'h2C, p2); axil_write(18'h30, p3);
        axil_write(18'h00, 32'd1);   // start
        st=0; for (i=0;i<4000 && !st[1];i=i+1) axil_read(18'h04, st);
    end endtask

    task check(input [127:0] name, input integer use_blur);
        reg [31:0] e;
    begin
        for (i=0;i<16;i=i+1) begin
            axil_read(18'h20000 + i*4, got);
            e = use_blur ? ebl[i] : eid[i];
            if (got !== e) begin errors=errors+1;
                $display("  FAIL %0s [%0d] got=%08x exp=%08x", name, i, got, e); end
        end
        $display("  %0s done (STATUS=%08x)", name, st);
    end endtask

    initial begin
        awvalid=0; wvalid=0; bready=0; arvalid=0; rready=0; wstrb=0; awaddr=0; araddr=0; wdata=0;
        img[0]=32'h001e1e1e; img[1]=32'h00c8c8c8; img[2]=32'h003c3c3c; img[3]=32'h00f0f0f0;
        img[4]=32'h00d2d2d2; img[5]=32'h00141414; img[6]=32'h00bebebe; img[7]=32'h00323232;
        img[8]=32'h00464646; img[9]=32'h00b4b4b4; img[10]=32'h005a5a5a; img[11]=32'h00a0a0a0;
        img[12]=32'h00e6e6e6; img[13]=32'h00282828; img[14]=32'h00969696; img[15]=32'h00505050;
        // identity = 输入
        for (i=0;i<16;i=i+1) eid[i]=img[i];
        // blur (Python ref_conv)
        ebl[0]=32'h00787878; ebl[1]=32'h007d7d7d; ebl[2]=32'h009d9d9d; ebl[3]=32'h00ababab;
        ebl[4]=32'h007f7f7f; ebl[5]=32'h00838383; ebl[6]=32'h00949494; ebl[7]=32'h009b9b9b;
        ebl[8]=32'h009d9d9d; ebl[9]=32'h00939393; ebl[10]=32'h00787878; ebl[11]=32'h007e7e7e;
        ebl[12]=32'h00a5a5a5; ebl[13]=32'h00939393; ebl[14]=32'h00797979; ebl[15]=32'h00808080;

        repeat(10) @(posedge clk); #1; rst=0; repeat(4) @(posedge clk);
        load_img;
        run_conv(32'h00000000, 32'h00000001, 32'h00000000, 32'h00000000); check("identity", 0);
        run_conv(32'h01010101, 32'h01010101, 32'h00000301, 32'h00000000); check("blur", 1);

        if (errors==0) $display("==> CONV SIM: ALL PASS");
        else           $display("==> CONV SIM: %0d ERRORS", errors);
        $finish;
    end
    initial begin #500000; $display("TIMEOUT"); $finish; end
endmodule
`default_nettype wire
