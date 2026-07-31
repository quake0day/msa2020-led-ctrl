// =====================================================================
// xk264 ext_ 参考帧存储控制器 (FPGA 可综合, 片上 M20K)
//   实现 mem_arbiter 的外部存储协议 (8 模式: load/store × Y/UV × deblock/ref)。
//   结构照搬 xk264 tb_top.v 里作者注释掉的时钟 FSM (446-623行), 只把稀疏地址
//   {ref_sel, luma/chroma, mb_y, mb_x, cnt} 换成紧凑地址 (mb_linear = mb_y*W+mb_x),
//   使参考帧能放进片上 M20K (中小分辨率, 免 DDR)。
//
//   ext_mode[2:0]:  [2]=store(1)/load(0)  [1]=chroma(1)/luma(0)  [0]=ref-sel 相关
//     000 load_db_y  010 load_db_uv  001 load_y   011 load_uv
//     100 store_db_y 110 store_db_uv 101 store_y  111 store_uv
// =====================================================================
`resetall
`timescale 1ns / 1ps
`default_nettype none

module h264_ext_mem #
(
    parameter MAX_MBS   = 512,             // 支持的最大 MB 数 (CIF=396)
    parameter MB_BITS   = 9,               // clog2(MAX_MBS)
    parameter AW        = MB_BITS + 2 + 5  // {plane(2), mb_linear(MB_BITS), cnt(5)}
)
(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         frame_parity,      // 当前帧奇偶 (双缓冲)
    input  wire [7:0]   mb_x_total,        // 帧宽(MB) 用于 mb_linear
    // 来自编码器 top 的 ext_ 输出
    input  wire         ext_start,
    input  wire [2:0]   ext_mode,
    input  wire [7:0]   ext_mb_x,
    input  wire [7:0]   ext_mb_y,
    input  wire [127:0] ext_data_o,        // store 时编码器给出的数据
    // 到编码器 top 的 ext_ 输入
    output wire         ext_done,
    output wire         ext_wen,
    output wire         ext_ren,
    output wire [3:0]   ext_addr,
    output reg  [127:0] ext_data_i
);
    localparam IDLE = 1'b0, RUN = 1'b1;
    localparam integer DEPTH = 4 * MAX_MBS * 32;

    (* ramstyle = "M20K" *) reg [63:0] ref_mem [0:DEPTH-1];

    reg  [5:0]  ref_cnt, ref_cnt_r;
    reg         state;
    // 紧凑 MB 线性地址 (ext_start 时锁存)
    reg  [MB_BITS-1:0] mb_lin;
    // 数据寄存 (load 路径)
    reg [31:0] a0,a1,a2,a3,b0,b1,b2,b3,c0,c1,c2,c3,d0,d1,d2,d3;
    reg [63:0] ref_mem_rdata;
    reg        ref_mem_wen;

    wire       ref_sel = ({ext_mode[2],ext_mode[0]}==2'b01) ? ~frame_parity : frame_parity;
    wire [AW-1:0] cnt_field = ext_mode[2] ? {1'b0,ref_cnt_r[4:0]} : {1'b0,ref_cnt[4:0]};
    wire [1:0] plane = {ref_sel, ext_mode[1]};
    // 紧凑地址 = plane*MAX_MBS*32 + mb_lin*32 + cnt
    wire [AW-1:0] ref_mem_addr = (plane * (MAX_MBS*32)) + (mb_lin * 32) + cnt_field[4:0];
    wire       ref_mem_cen  = ext_mode[2] ? ref_mem_wen : (state==RUN);

    // ------------- 状态机 -------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin state <= IDLE; ref_cnt_r <= 0; end
        else begin
            ref_cnt_r <= ref_cnt;
            case (state)
                IDLE: if (ext_start) state <= RUN;
                RUN : if ((ext_mode[1]==1'b0 && ref_cnt==6'h1f) ||
                          (ext_mode[1]==1'b1 && ref_cnt==6'hf)) state <= IDLE;
            endcase
        end
    end

    // ext_start 时锁存 mb_linear = mb_y*mb_x_total + mb_x
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) mb_lin <= 0;
        else if (ext_start && state==IDLE) mb_lin <= (ext_mb_y * mb_x_total + ext_mb_x);
    end

    // ------------- 计数 -------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) ref_cnt <= 0;
        else if (ext_done) ref_cnt <= 0;
        else if (state==IDLE && ext_start) begin
            if      (ext_mode[1:0]==2'b00) ref_cnt <= 6'h18;  // db_y
            else if (ext_mode[1:0]==2'b10) ref_cnt <= 6'h08;  // db_uv
            else                           ref_cnt <= 6'h00;
        end
        else if (state==RUN) ref_cnt <= ref_cnt + 1'b1;
    end

    // ------------- 读 ref_mem -> 4x4 寄存 -------------
    always @(posedge clk) begin
        if (ref_mem_cen && ~ref_mem_wen) ref_mem_rdata <= ref_mem[ref_mem_addr];
    end
    always @(posedge clk) begin
        if (ref_mem_cen && ~ref_mem_wen) begin
            case (ref_mem_addr[2:0])
                3'b000: {a1,a0} <= ref_mem[ref_mem_addr];
                3'b001: {a3,a2} <= ref_mem[ref_mem_addr];
                3'b010: {b1,b0} <= ref_mem[ref_mem_addr];
                3'b011: {b3,b2} <= ref_mem[ref_mem_addr];
                3'b100: {c1,c0} <= ref_mem[ref_mem_addr];
                3'b101: {c3,c2} <= ref_mem[ref_mem_addr];
                3'b110: {d1,d0} <= ref_mem[ref_mem_addr];
                3'b111: {d3,d2} <= ref_mem[ref_mem_addr];
            endcase
        end
    end

    // ------------- 写 ref_mem (store) -------------
    reg [63:0] ref_mem_wdata;
    always @(*) ref_mem_wdata = ref_cnt_r[0] ? ext_data_o[127:64] : ext_data_o[63:0];
    always @(posedge clk) begin
        if (ref_mem_cen && ref_mem_wen) ref_mem[ref_mem_addr] <= ref_mem_wdata;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) ref_mem_wen <= 1'b0;
        else if (state==RUN && ext_mode[2]==1'b1) ref_mem_wen <= 1'b1;
        else ref_mem_wen <= 1'b0;
    end

    // ------------- done -------------
    reg ext_done_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) ext_done_r <= 1'b0;
        else if (state==IDLE && ((ext_mode[1]==1'b0 && ref_cnt_r==6'h1f) ||
                                 (ext_mode[1]==1'b1 && ref_cnt_r==6'hf))) ext_done_r <= 1'b1;
        else ext_done_r <= 1'b0;
    end
    assign ext_done = ext_done_r;

    // ------------- store 时驱动 ren/addr -------------
    assign ext_ren  = (state==RUN) && (ext_mode[2]==1'b1);
    assign ext_addr = ext_mode[2] ? ref_cnt[4:1] : ref_cnt_r[4:1];

    // ------------- load 时驱动 wen -------------
    reg ext_wen_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) ext_wen_r <= 1'b0;
        else if (state==RUN && ext_mode[2]==1'b0) begin
            if      (ext_mode[0]==1'b1 && ref_cnt>=6'h3) ext_wen_r <= 1'b1;
            else if (ext_mode[0]==1'b0 && ref_cnt[0]==1'b1) ext_wen_r <= 1'b1;
            else ext_wen_r <= 1'b0;
        end
        else ext_wen_r <= 1'b0;
    end
    assign ext_wen = ext_wen_r;

    // ------------- load 时驱动 ext_data_i -------------
    always @(*) begin
        if (ext_mode[0]==1'b1)
            case (ref_cnt[2:0])
                3'b000: ext_data_i = {64'b0, d0, c0};
                3'b001: ext_data_i = {64'b0, d1, c1};
                3'b010: ext_data_i = {64'b0, d2, c2};
                3'b011: ext_data_i = {64'b0, d3, c3};
                3'b100: ext_data_i = {64'b0, b0, a0};
                3'b101: ext_data_i = {64'b0, b1, a1};
                3'b110: ext_data_i = {64'b0, b2, a2};
                3'b111: ext_data_i = {64'b0, b3, a3};
            endcase
        else
            case (ref_cnt_r[2:0])
                3'b000,3'b001: ext_data_i = {a3,a2,a1,a0};
                3'b010,3'b011: ext_data_i = {b3,b2,b1,b0};
                3'b100,3'b101: ext_data_i = {c3,c2,c1,c0};
                default:       ext_data_i = {d3,d2,d1,d0};
            endcase
    end
endmodule
`resetall
