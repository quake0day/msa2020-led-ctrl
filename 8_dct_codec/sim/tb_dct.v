// 功能仿真: dct_accel FDCT + IDCT, 对照 gen_dct.py 参考(hex 向量)。
`timescale 1ns/1ps
`default_nettype none
module tb;
    reg clk=0, rst=1;
    always #2 clk=~clk;
    reg  [17:0] awaddr, araddr; reg [31:0] wdata; reg [3:0] wstrb;
    reg  awvalid, wvalid, bready, arvalid, rready;
    wire awready, wready, bvalid, arready, rvalid;
    wire [31:0] rdata; wire [1:0] bresp, rresp;

    dct_accel #(.DATA_WIDTH(32), .ADDR_WIDTH(18)) dut (
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
    reg [31:0] pixin [0:63];
    reg [31:0] fdct  [0:63];
    reg [31:0] idctp [0:63];
    reg [31:0] got, st;

    task write_block(input [1:0] which);   // 0=pixin, 1=fdct
    begin
        for (i=0;i<64;i=i+1)
            axil_write(18'h10000 + i*4, which==0 ? pixin[i] : fdct[i]);
    end endtask

    task run(input [31:0] mode);
    begin
        axil_write(18'h08, mode);     // MODE
        axil_write(18'h14, 32'd1);    // COUNT = 1 block
        axil_write(18'h18, 32'd1);    // PARAM0 = lshift
        axil_write(18'h00, 32'd1);    // start
        st=0; for (i=0;i<20000 && !st[1];i=i+1) axil_read(18'h04, st);
    end endtask

    task check(input [63:0] name, input [1:0] which);  // which: 1=fdct exp, 2=idctp exp
        reg [31:0] e;
    begin
        for (i=0;i<64;i=i+1) begin
            axil_read(18'h20000 + i*4, got);
            e = (which==1) ? fdct[i] : idctp[i];
            if (got !== e) begin errors=errors+1;
                if (errors<=8) $display("  FAIL %0s [%0d] got=%08x exp=%08x", name, i, got, e); end
        end
        $display("  %0s done (STATUS=%08x)", name, st);
    end endtask

    initial begin
        $readmemh("sim/pixin.hex", pixin);
        $readmemh("sim/fdct.hex",  fdct);
        $readmemh("sim/idctpix.hex", idctp);
        awvalid=0; wvalid=0; bready=0; arvalid=0; rready=0; wstrb=0; awaddr=0; araddr=0; wdata=0;
        repeat(10) @(posedge clk); #1; rst=0; repeat(4) @(posedge clk);

        axil_read(18'h3C, got);
        if (got !== 32'h44435438) begin errors=errors+1; $display("  FAIL ID=%08x (exp DCT8)", got); end
        else $display("  ID = DCT8 OK");

        // FDCT: 写像素块 -> 变换 -> 对照 fdct 系数
        write_block(0); run(32'd0); check("FDCT", 1);
        // IDCT: 写 fdct 系数 -> 反变换 -> 对照 idctpix
        write_block(1); run(32'd1); check("IDCT", 2);

        if (errors==0) $display("==> DCT SIM: ALL PASS");
        else           $display("==> DCT SIM: %0d ERRORS", errors);
        $finish;
    end
    initial begin #2000000; $display("TIMEOUT"); $finish; end
endmodule
`default_nettype wire
