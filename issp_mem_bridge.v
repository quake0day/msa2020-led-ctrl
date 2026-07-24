// issp_mem_bridge -- ISSP -> Avalon-MM 单次读写命令桥
// 上位机经第二个 ISSP 实例 (instance_id=MEM) 发内存读写命令,
// FSM 执行一次 Avalon 事务后把结果/序号回写探针。
// 当前 Avalon 主口接片内 RAM 验证链路; DDR4 到位后改接 EMIF 即可。
//
// source[95:0] (电脑 -> FPGA):
//   [31:0]  写数据
//   [61:32] 字地址 (FSM 左移2位转字节地址)
//   [62]    1=写, 0=读
//   [71:64] 命令序号 (与上次不同即触发执行, 上位机从 1 开始递增)
// probe[63:0] (FPGA -> 电脑):
//   [31:0]  读回数据
//   [39:32] 已完成命令序号 (等于发出的序号 = 执行完毕)
//   [43:40] 心跳
//   [46:44] 电源状态 {DDR_LDO_GD, SWITCH_GD, 12V}
//   [51:48] 各通道校准成功 ok[3:0]  [55:52] 各通道校准失败 fail[3:0]
//   [63:56] 签名 0xA5
//   [79:64] 各 ref_clk 输入活动计数 (每通道4位; 增长=参考时钟脚有信号)
//   [95:80] 各 EMIF usr_clk 活动计数 (每通道4位; 读两次若增长=PLL锁定)
module issp_mem_bridge (
    input  wire        clk,
    input  wire [95:0] src,
    output wire [95:0] prb,
    input  wire [3:0]  heartbeat,
    input  wire [3:0]  cal_ok,         // 各 DDR4 通道校准成功
    input  wire [3:0]  cal_fail,       // 各 DDR4 通道校准失败
    input  wire [2:0]  pwr,            // {DDR_LDO_GD, SWITCH_GD, 12V}
    input  wire [15:0] usr_alive,      // 各 EMIF usr_clk 活动计数 (每通道4位)
    input  wire [15:0] ref_alive,      // 各 ref_clk 输入活动计数 (每通道4位)
    // Avalon-MM master (32-bit)
    output reg  [31:0] am_address,
    output reg         am_read,
    output reg         am_write,
    output reg  [31:0] am_writedata,
    output wire [3:0]  am_byteenable,
    input  wire [31:0] am_readdata,
    input  wire        am_readdatavalid,
    input  wire        am_waitrequest
);

assign am_byteenable = 4'hF;

// ISSP 源来自 JTAG 时钟域, 打两拍同步 (单条命令由一次移位原子更新)
reg [95:0] s1 = 96'd0, s2 = 96'd0;
always @(posedge clk) begin
    s1 <= src;
    s2 <= s1;
end

wire [31:0] c_wdata = s2[31:0];
wire [29:0] c_addr  = s2[61:32];
wire        c_we    = s2[62];
wire [7:0]  c_seq   = s2[71:64];

localparam ST_IDLE = 2'd0, ST_ISSUE = 2'd1, ST_RDATA = 2'd2;

reg [1:0]  state    = ST_IDLE;
reg [7:0]  seq_done = 8'd0;
reg [31:0] rdata    = 32'd0;

always @(posedge clk) begin
    case (state)
        ST_IDLE: begin
            am_read  <= 1'b0;
            am_write <= 1'b0;
            if (c_seq != seq_done && c_seq != 8'd0) begin
                am_address   <= {c_addr, 2'b00};
                am_writedata <= c_wdata;
                am_read      <= ~c_we;
                am_write     <=  c_we;
                state        <= ST_ISSUE;
            end
        end
        ST_ISSUE: if (!am_waitrequest) begin
            am_read  <= 1'b0;
            am_write <= 1'b0;
            if (am_read)
                state <= ST_RDATA;         // 读命令: 还要等数据返回
            else begin
                seq_done <= c_seq;         // 写命令: 被接受即完成
                state    <= ST_IDLE;
            end
        end
        ST_RDATA: if (am_readdatavalid) begin
            rdata    <= am_readdata;
            seq_done <= c_seq;
            state    <= ST_IDLE;
        end
        default: state <= ST_IDLE;
    endcase
end

assign prb = {usr_alive, ref_alive, 8'hA5, cal_fail, cal_ok, 1'b0, pwr,
              heartbeat, seq_done, rdata};

endmodule
