// tb_led_ctrl_core -- 直接驱动 Avalon-MM 从接口, 验证寄存器与灯效切换
// (JTAG 桥为 Intel 成熟 IP, 仿真中跳过, 上板由 System Console 验证)
`timescale 1ns/1ps
module tb_led_ctrl_core;

reg         clk = 0;
reg  [31:0] av_address = 0;
reg         av_read = 0, av_write = 0;
reg  [31:0] av_writedata = 0;
wire [31:0] av_readdata;
wire        av_readdatavalid, av_waitrequest;
wire [8:0]  LED;

reg  [15:0] issp_source = 16'd0;
wire [31:0] issp_probe;

led_ctrl_core dut (
    .clk(clk),
    .av_address(av_address), .av_read(av_read), .av_write(av_write),
    .av_writedata(av_writedata), .av_readdata(av_readdata),
    .av_readdatavalid(av_readdatavalid), .av_waitrequest(av_waitrequest),
    .issp_source(issp_source), .issp_probe(issp_probe),
    .LED(LED)
);

always #5 clk = ~clk;

integer errors = 0;

task wr(input [31:0] addr, input [31:0] data);
begin
    @(negedge clk);
    av_address = addr; av_writedata = data; av_write = 1;
    @(negedge clk);
    av_write = 0;
end
endtask

task rd(input [31:0] addr, output [31:0] data);
begin
    @(negedge clk);
    av_address = addr; av_read = 1;
    @(negedge clk);
    av_read = 0;
    if (av_readdatavalid !== 1'b1) begin
        errors = errors + 1;
        $display("FAIL: addr %h readdatavalid 未拉高", addr);
    end
    data = av_readdata;
end
endtask

task expect_reg(input [31:0] addr, input [31:0] want, input [255:0] name);
reg [31:0] got;
begin
    rd(addr, got);
    if (got !== want) begin
        errors = errors + 1;
        $display("FAIL: %0s = %h, 期望 %h", name, got, want);
    end else
        $display("PASS: %0s = %h", name, got);
end
endtask

reg [31:0] v;
initial begin
    repeat (10) @(posedge clk);

    // ID 与默认值
    expect_reg(32'h00, 32'hA2020001, "ID");
    expect_reg(32'h04, 32'd0, "CTRL 默认(自动)");

    // 手动模式: LED 应直接等于 MANUAL 寄存器
    wr(32'h04, 32'd5);            // CTRL = 手动
    wr(32'h08, 32'h155);          // MANUAL = 101010101
    repeat (4) @(posedge clk);
    if (LED !== 9'h155) begin
        errors = errors + 1;
        $display("FAIL: 手动模式 LED = %b, 期望 101010101", LED);
    end else $display("PASS: 手动模式 LED = %b", LED);
    expect_reg(32'h08, 32'h155, "MANUAL 回读");

    // 流水灯模式: LED 应为独热码
    wr(32'h04, 32'd2);
    repeat (10) @(posedge clk);
    if (LED === 9'd0 || (LED & (LED - 1)) !== 9'd0) begin
        errors = errors + 1;
        $display("FAIL: 流水灯模式 LED = %b, 期望独热码", LED);
    end else $display("PASS: 流水灯模式 LED = %b (独热)", LED);

    // 非法模式值应被钳位到 5
    wr(32'h04, 32'd7);
    expect_reg(32'h04, 32'd5, "CTRL 非法值钳位");

    // 速度寄存器 & PHASE 活动性
    wr(32'h0C, 32'd3);
    expect_reg(32'h0C, 32'd3, "SPEED");
    rd(32'h14, v);
    #100;
    begin : phase_check
        reg [31:0] v2;
        rd(32'h14, v2);
        if (v2 === v) begin
            errors = errors + 1;
            $display("FAIL: PHASE 计数器没有变化 (%h)", v);
        end else $display("PASS: PHASE 在计数 (%h -> %h)", v, v2);
    end

    // ISSP 接管: bit15=1, 速度=0, 手动LED=0x0AA, 模式=5(手动)
    issp_source = 16'h8555;
    repeat (8) @(posedge clk);
    if (LED !== 9'h0AA) begin
        errors = errors + 1;
        $display("FAIL: ISSP 接管 LED = %b, 期望 010101010", LED);
    end else $display("PASS: ISSP 接管 LED = %b", LED);
    if (issp_probe[31:24] !== 8'h5A) begin
        errors = errors + 1;
        $display("FAIL: ISSP probe 签名 = %h, 期望 5A", issp_probe[31:24]);
    end else $display("PASS: ISSP probe 签名/内容 = %h", issp_probe);
    issp_source = 16'd0;                 // 释放, 交还 Avalon 控制
    repeat (8) @(posedge clk);
    if (LED === 9'h0AA) begin
        errors = errors + 1;
        $display("FAIL: ISSP 释放后 LED 未交还 Avalon 控制");
    end else $display("PASS: ISSP 释放, 控制交还 Avalon");

    if (errors == 0) $display("ALL PASS");
    else $display("共 %0d 个失败", errors);
    $finish;
end

endmodule
