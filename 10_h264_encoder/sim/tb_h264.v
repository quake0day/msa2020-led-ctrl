// 自写 H.264 编码仿真台 (不复用 xk264 的 tb_top.v):
//   喂 MB-tiled YUV -> xk264 top -> 我的 ext_ 控制器 -> 抓 winc_o 码流写 out.264
`timescale 1ns/1ps
`default_nettype none
module tb_h264;
    localparam MBX = 6, MBY = 4;          // 与 gen_yuv.py 一致 (96x64)
    localparam NWORDS = MBX*MBY*96;

    reg clk=0, rst_n=0;
    always #5 clk=~clk;

    // ---- 控制 ----
    reg  sys_start=0, sys_intra_flag=0, sys_mode=0;
    reg  [5:0] sys_qp=27;
    reg  [7:0] sys_x_total, sys_y_total;
    wire sys_done, enc_ld_start;
    wire [7:0] enc_ld_x, enc_ld_y;
    // ---- 输入 ----
    reg  rvalid_i=0; wire rinc_o; reg [63:0] rdata_i=0;
    // ---- 输出 ----
    reg  wfull_i=0; wire winc_o; wire [7:0] wdata_o;
    // ---- ext ----
    wire        ext_start, ext_done, ext_wen, ext_ren;
    wire [2:0]  ext_mode;
    wire [7:0]  ext_mb_x, ext_mb_y;
    wire [3:0]  ext_addr;
    wire [127:0] ext_data_i, ext_data_o;

    top u_top (
        .clk(clk), .rst_n(rst_n),
        .sys_start(sys_start), .sys_done(sys_done), .sys_intra_flag(sys_intra_flag),
        .sys_qp(sys_qp), .sys_mode(sys_mode), .sys_x_total(sys_x_total), .sys_y_total(sys_y_total),
        .enc_ld_start(enc_ld_start), .enc_ld_x(enc_ld_x), .enc_ld_y(enc_ld_y),
        .rdata_i(rdata_i), .rvalid_i(rvalid_i), .rinc_o(rinc_o),
        .wdata_o(wdata_o), .wfull_i(wfull_i), .winc_o(winc_o),
        .ext_mb_x_o(ext_mb_x), .ext_mb_y_o(ext_mb_y), .ext_start_o(ext_start),
        .ext_done_i(ext_done), .ext_mode_o(ext_mode), .ext_wen_i(ext_wen), .ext_ren_i(ext_ren),
        .ext_addr_i(ext_addr), .ext_data_i(ext_data_i), .ext_data_o(ext_data_o)
    );

    h264_ext_mem #(.MAX_MBS(512)) u_ext (
        .clk(clk), .rst_n(rst_n), .frame_parity(1'b0), .mb_x_total(MBX[7:0]),
        .ext_start(ext_start), .ext_mode(ext_mode), .ext_mb_x(ext_mb_x), .ext_mb_y(ext_mb_y),
        .ext_data_o(ext_data_o),
        .ext_done(ext_done), .ext_wen(ext_wen), .ext_ren(ext_ren), .ext_addr(ext_addr),
        .ext_data_i(ext_data_i)
    );

    // ---- 输入喂帧 (48 字/MB, 每字 2 个 pixel_ram) ----
    reg [31:0] pixel_ram [0:NWORDS-1];
    reg [31:0] addr_r=0, cnt=0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin rdata_i<=0; rvalid_i<=0; addr_r<=0; end
        else if (rinc_o && cnt!=32'd48) begin
            rdata_i  <= {pixel_ram[2*addr_r+0], pixel_ram[2*addr_r+1]};
            rvalid_i <= 1'b1; addr_r <= addr_r + 1'b1;
        end else begin rdata_i<=0; rvalid_i<=0; end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cnt<=0; else if (rinc_o) cnt<=cnt+1'b1; else cnt<=0;
    end

    // ---- 抓码流 + 监视 ----
    integer fout, bs=0, rinc_cnt=0, ext_cnt=0;
    always @(posedge clk) if (rst_n && winc_o) begin
        $fwrite(fout, "%c", wdata_o); bs=bs+1;
    end
    always @(posedge clk) if (rst_n && rinc_o) rinc_cnt=rinc_cnt+1;
    always @(posedge clk) if (rst_n && ext_start) ext_cnt=ext_cnt+1;

    initial begin
        $readmemh("input.dat", pixel_ram);
        fout = $fopen("out.264","wb");
        sys_x_total = MBX-1; sys_y_total = MBY-1;
        #100 rst_n=1;
        #200;
        @(posedge clk); sys_intra_flag<=1'b1;          // I 帧
        @(posedge clk); sys_start<=1'b1;
        @(posedge clk); sys_start<=1'b0;
        repeat(8) @(posedge clk);                      // 让 sys_done 落 0 (避开 NBA 竞态)
        wait(sys_done==1'b0);                          // 确认进入编码
        $display("t=%0t encoding started (sys_done=0)", $time);
        wait(sys_done==1'b1);                          // 等编码完成
        #3000;
        $display("=== ENCODE DONE: bs=%0d bytes, rinc=%0d, ext=%0d ===", bs, rinc_cnt, ext_cnt);
        $fclose(fout);
        $finish;
    end
    // 每 20us 打点, 便于观察是否卡住
    initial forever begin #20000; $display("  t=%0t done=%b rinc=%0d ext=%0d bs=%0d ldx=%0d ldy=%0d",
                                            $time, sys_done, rinc_cnt, ext_cnt, bs, enc_ld_x, enc_ld_y); end
    initial begin #300000000; $display("*** TIMEOUT (bs=%0d rinc=%0d ext=%0d) ***", bs, rinc_cnt, ext_cnt); $fclose(fout); $finish; end
endmodule
`default_nettype wire
