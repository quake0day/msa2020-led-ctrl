// tb_issp_mem_bridge -- 用带随机等待的 Avalon RAM 模型验证命令桥
`timescale 1ns/1ps
module tb_issp_mem_bridge;

reg clk = 0;
always #5 clk = ~clk;

reg  [95:0] src = 96'd0;
wire [63:0] prb;
wire [31:0] am_address, am_writedata;
wire [31:0] am_readdata;
wire        am_read, am_write;
wire [3:0]  am_byteenable;

issp_mem_bridge dut (
    .clk(clk), .src(src), .prb(prb), .heartbeat(4'h7),
    .am_address(am_address), .am_read(am_read), .am_write(am_write),
    .am_writedata(am_writedata), .am_byteenable(am_byteenable),
    .am_readdata(am_readdata), .am_readdatavalid(am_readdatavalid),
    .am_waitrequest(am_waitrequest)
);

// ---- Avalon RAM 模型: 随机 waitrequest, 读延迟 2 拍 ----
reg [31:0] mem [0:63];
reg [2:0]  lfsr = 3'b101;
always @(posedge clk) lfsr <= {lfsr[1:0], lfsr[2] ^ lfsr[1]};
assign am_waitrequest = lfsr[0];

reg        rd_p1 = 0, rd_p2 = 0;
reg [31:0] rdata_p1, rdata_p2;
always @(posedge clk) begin
    rd_p1 <= 0;
    if (!am_waitrequest) begin
        if (am_write) mem[am_address[7:2]] <= am_writedata;
        if (am_read)  begin rd_p1 <= 1; rdata_p1 <= mem[am_address[7:2]]; end
    end
    rd_p2 <= rd_p1; rdata_p2 <= rdata_p1;
end
assign am_readdatavalid = rd_p2;
assign am_readdata      = rdata_p2;

// ---- 激励 ----
integer errors = 0;
reg [7:0] seq = 0;

task cmd(input we, input [29:0] addr, input [31:0] wdata);
integer n;
begin
    seq = seq + 1;
    src = {24'd0, seq, 1'b0, we, addr, wdata};
    n = 0;
    while (prb[39:32] !== seq && n < 200) begin @(posedge clk); n = n + 1; end
    if (prb[39:32] !== seq) begin
        errors = errors + 1;
        $display("FAIL: seq %0d 超时未完成", seq);
    end
end
endtask

reg [31:0] got;
integer i;
initial begin
    repeat (10) @(posedge clk);
    if (prb[63:56] !== 8'hA5) begin errors = errors + 1; $display("FAIL: 签名"); end

    // 写 8 个字再读回比对
    for (i = 0; i < 8; i = i + 1)
        cmd(1'b1, i[29:0], 32'hC0DE0000 + i * 17);
    for (i = 0; i < 8; i = i + 1) begin
        cmd(1'b0, i[29:0], 32'h0);
        got = prb[31:0];
        if (got !== 32'hC0DE0000 + i * 17) begin
            errors = errors + 1;
            $display("FAIL: 地址 %0d 读回 %h, 期望 %h", i, got, 32'hC0DE0000 + i * 17);
        end
    end
    if (errors == 0) $display("ALL PASS (8写8读, 随机waitrequest, 读延迟2拍)");
    else $display("共 %0d 个失败", errors);
    $finish;
end

endmodule
