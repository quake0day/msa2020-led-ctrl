// PRBS31 (x^31 + x^28 + 1) 并行生成器与自同步检验器
// LSB-first 串行序约定 (与增强 PCS basic 模式一致)

module prbs31_gen #(
    parameter W = 80
) (
    input  wire         clk,
    input  wire         rst,
    output reg  [W-1:0] dout
);

reg [30:0] st = 31'h7FFF_FFFF;

reg [30:0]  s;
reg [W-1:0] o;
integer i;
always @* begin
    s = st;
    for (i = 0; i < W; i = i + 1) begin
        o[i] = s[30] ^ s[27];
        s = {s[29:0], o[i]};
    end
end

always @(posedge clk) begin
    if (rst) begin
        st   <= 31'h7FFF_FFFF;
        dout <= '0;
    end else begin
        st   <= s;
        dout <= o;
    end
end

endmodule


// 自同步检验器: err = d[n] ^ d[n-28] ^ d[n-31], 与字对齐无关
module prbs31_chk #(
    parameter W = 80
) (
    input  wire         clk,
    input  wire         rst,
    input  wire [W-1:0] din,
    input  wire         clear,
    output reg  [31:0]  err_count,
    output reg          err_seen
);

reg [30:0] hist = '0;
wire [W+30:0] stream = {din, hist};

reg [W-1:0] e;
integer i;
always @* begin
    for (i = 0; i < W; i = i + 1)
        e[i] = stream[i+31] ^ stream[i+3] ^ stream[i];
end

reg [7:0]  pop_r;
reg        warm = 1'b0, warm_r = 1'b0;   // 上电首字含无效历史, 跳过
always @(posedge clk) begin
    if (rst) begin
        hist <= '0;
        warm <= 1'b0;
        warm_r <= 1'b0;
        pop_r <= '0;
        err_count <= '0;
        err_seen <= 1'b0;
    end else begin
        hist <= din[W-1 -: 31];
        warm <= 1'b1;
        warm_r <= warm;
        pop_r <= $countones(e);
        if (clear) begin
            err_count <= '0;
            err_seen <= 1'b0;
        end else if (warm_r && pop_r != 0) begin
            err_seen <= 1'b1;
            if (!(&err_count))
                err_count <= (err_count + pop_r < err_count) ? 32'hFFFF_FFFF
                                                             : err_count + pop_r;
        end
    end
end

endmodule
