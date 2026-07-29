// 功能仿真: axil_ddr_bridge, 用桩 Avalon 从机(假内存)验证 AXI-Lite<->Avalon 跨时钟。
`timescale 1ns/1ps
`default_nettype none
module tb;
    reg pclk=0, mclk=0, rst=1;
    always #2 pclk=~pclk;    // pcie_clk 快
    always #7 mclk=~mclk;    // mem_clk 慢 (异步)

    reg  [17:0] awaddr, araddr; reg [31:0] wdata; reg [3:0] wstrb;
    reg  awvalid, wvalid, bready, arvalid, rready;
    wire awready, wready, bvalid, arready, rvalid;
    wire [31:0] rdata; wire [1:0] bresp, rresp;

    wire [35:0] avm_addr; wire avm_read, avm_write;
    wire [31:0] avm_wdata; wire [3:0] avm_be;
    reg  [31:0] avm_rdata; reg avm_rdv; wire avm_wait;

    axil_ddr_bridge #(.DATA_WIDTH(32), .ADDR_WIDTH(18), .AVMM_ADDR_WIDTH(36)) dut (
        .clk(pclk), .rst(rst),
        .s_axil_awaddr(awaddr), .s_axil_awprot(3'd0), .s_axil_awvalid(awvalid), .s_axil_awready(awready),
        .s_axil_wdata(wdata), .s_axil_wstrb(wstrb), .s_axil_wvalid(wvalid), .s_axil_wready(wready),
        .s_axil_bresp(bresp), .s_axil_bvalid(bvalid), .s_axil_bready(bready),
        .s_axil_araddr(araddr), .s_axil_arprot(3'd0), .s_axil_arvalid(arvalid), .s_axil_arready(arready),
        .s_axil_rdata(rdata), .s_axil_rresp(rresp), .s_axil_rvalid(rvalid), .s_axil_rready(rready),
        .mem_clk(mclk),
        .avm_address(avm_addr), .avm_read(avm_read), .avm_write(avm_write),
        .avm_writedata(avm_wdata), .avm_byteenable(avm_be),
        .avm_readdata(avm_rdata), .avm_readdatavalid(avm_rdv), .avm_waitrequest(avm_wait),
        .cal_ok0(1'b1), .cal_ok1(1'b1)
    );
    assign avm_wait = 1'b0;   // 桩: 永远就绪

    // 桩 Avalon 从机: 256 字假内存, 读延迟 1 拍
    reg [31:0] fmem [0:255];
    always @(posedge mclk) begin
        avm_rdv <= 1'b0;
        if (avm_write) fmem[avm_addr[9:2]] <= avm_wdata;
        if (avm_read) begin avm_rdata <= fmem[avm_addr[9:2]]; avm_rdv <= 1'b1; end
    end

    task axil_write(input [17:0] a, input [31:0] d);
    begin
        @(posedge pclk); #1; awaddr=a; wdata=d; wstrb=4'hF; awvalid=1; wvalid=1; bready=1;
        @(posedge pclk); while (!bvalid) @(posedge pclk);
        #1; awvalid=0; wvalid=0; @(posedge pclk); #1; bready=0;
    end endtask
    task axil_read(input [17:0] a, output [31:0] d);
    begin
        @(posedge pclk); #1; araddr=a; arvalid=1; rready=1;
        @(posedge pclk); while (!rvalid) @(posedge pclk);
        d = rdata; #1; arvalid=0; @(posedge pclk); #1; rready=0;
    end endtask

    integer errors=0, i;
    reg [31:0] got;

    initial begin
        awvalid=0; wvalid=0; bready=0; arvalid=0; rready=0; wstrb=0; awaddr=0; araddr=0; wdata=0;
        avm_rdata=0; avm_rdv=0;
        for (i=0;i<256;i=i+1) fmem[i]=0;
        repeat(20) @(posedge pclk); #1; rst=0; repeat(8) @(posedge pclk);

        // ID
        axil_read(18'h2000C, got);
        if (got!==32'h44445242) begin errors=errors+1; $display("  FAIL ID=%08x",got); end
        else $display("  ID = DDRB OK");
        // STATUS cal_ok
        axil_read(18'h20004, got);
        if ((got&2'b11)!==2'b11) begin errors=errors+1; $display("  FAIL STATUS=%08x",got); end
        else $display("  STATUS cal_ok OK (%08x)",got);

        // PAGE=0 -> 写数据窗口 (am 低地址) -> 经桥进假内存 -> 读回
        axil_write(18'h20000, 32'd0);   // PAGE=0
        for (i=0;i<8;i=i+1) axil_write(18'h00000 + i*4, 32'hBEEF0000 + i);
        for (i=0;i<8;i=i+1) begin
            axil_read(18'h00000 + i*4, got);
            if (got !== (32'hBEEF0000 + i)) begin errors=errors+1;
                $display("  FAIL data[%0d] got=%08x exp=%08x", i, got, 32'hBEEF0000+i); end
        end
        $display("  data window write/read done");

        if (errors==0) $display("==> BRIDGE SIM: ALL PASS");
        else           $display("==> BRIDGE SIM: %0d ERRORS", errors);
        $finish;
    end
    initial begin #500000; $display("TIMEOUT"); $finish; end
endmodule
`default_nettype wire
