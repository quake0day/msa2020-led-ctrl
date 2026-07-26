# =====================================================================
# led_panel.tcl -- MSA-2020 LED 控制面板 (System Console Dashboard, ISSP 版)
#
# 推荐优先使用独立 GUI: python led_gui.py
# 本脚本为 System Console 内使用的备用面板:
#   H:\fpga\syscon\bin\system-console --desktop_script=H:\led_ctrl\led_panel.tcl
#
# 注: 板卡的 Catapult 定制 JTAG 驱动不支持 JTAG-Avalon 流式传输,
#     因此使用 ISSP 通道 (与 led_gui.py 相同)。
# 命令行用法:
#   led::mode 2      ;# 0自动 1闪烁 2流水 3呼吸 4波浪 5手动
#   led::manual 0x155
#   led::speed 3
#   led::status
#   led::release     ;# 交还板卡控制权
# =====================================================================

namespace eval led {
    variable i ""
    variable cur_mode 0
    variable cur_manual 0
    variable cur_speed 0

    proc connect {} {
        variable i
        if {$i ne ""} { return }
        set paths [get_service_paths issp]
        if {[llength $paths] == 0} {
            error "未找到 ISSP 服务。请确认: 1) 板卡 USB 已连接 2) 已烧录 led_ctrl.sof 3) FT232H 驱动与 jtag_hw_microsoft_catapult.dll 已安装"
        }
        set i [lindex $paths 0]
        open_service issp $i
        set p [issp_read_probe_data $i]
        if {[expr {($p >> 24) & 0xFF}] != 0x5A} {
            puts "警告: 探针签名不是 0x5A, 板内可能不是 led_ctrl 工程"
        } else {
            puts "已连接 MSA-2020 led_ctrl (ISSP, 签名 0x5A)"
        }
    }

    proc push {} {
        variable i; variable cur_mode; variable cur_manual; variable cur_speed
        connect
        issp_write_source_data $i [expr {0x8000 | ($cur_speed << 12) \
                                         | (($cur_manual & 0x1FF) << 3) \
                                         | ($cur_mode & 7)}]
    }

    proc mode {v}   { variable cur_mode;   set cur_mode $v;   push }
    proc manual {v} { variable cur_manual; variable cur_mode
                      set cur_manual $v; set cur_mode 5; push }
    proc speed {v}  { variable cur_speed;  set cur_speed $v;  push }
    proc release {} { variable i; connect; issp_write_source_data $i 0 }

    proc status {} {
        variable i
        connect
        set p [issp_read_probe_data $i]
        set ledbits [expr {$p & 0x1FF}]
        set act     [expr {($p >> 9) & 7}]
        set mode    [expr {($p >> 12) & 7}]
        set names {自动轮换 计数器闪烁 流水灯 呼吸灯 波浪呼吸 手动}
        set pats  {计数器闪烁 流水灯 呼吸灯 波浪呼吸 手动}
        puts "模式: [lindex $names $mode] | 当前灯效: [lindex $pats $act] | LED: [format %09b $ledbits]"
        return $ledbits
    }
}

# ---------------------- Dashboard 图形面板 ----------------------
proc build_dashboard {} {
    set d [add_service dashboard led_panel "MSA-2020 LED 控制台" "Tools"]

    dashboard_add $d gM group self
    dashboard_set_property $d gM title "LED Pattern"
    dashboard_set_property $d gM itemsPerRow 3
    foreach {id txt val} {
        bAuto   "自动轮换"   0
        bBlink  "计数器闪烁" 1
        bScan   "流水灯"     2
        bBreath "呼吸灯"     3
        bWave   "波浪呼吸"   4
        bOff    "全灭(手动)" 5
    } {
        dashboard_add $d $id button gM
        dashboard_set_property $d $id text $txt
        if {$val == 5} {
            dashboard_set_property $d $id onClick "led::manual 0"
        } else {
            dashboard_set_property $d $id onClick "led::mode $val"
        }
    }

    dashboard_add $d gS group self
    dashboard_set_property $d gS title "速度档位 (0~5, 每档 x2)"
    dashboard_set_property $d gS itemsPerRow 6
    foreach v {0 1 2 3 4 5} {
        dashboard_add $d spd$v button gS
        dashboard_set_property $d spd$v text "x[expr {1 << $v}]"
        dashboard_set_property $d spd$v onClick "led::speed $v"
    }

    dashboard_add $d gMan group self
    dashboard_set_property $d gMan title "手动直控 (勾选后点应用)"
    dashboard_set_property $d gMan itemsPerRow 10
    for {set i 8} {$i >= 0} {incr i -1} {
        dashboard_add $d cb$i checkBox gMan
        dashboard_set_property $d cb$i text "LED$i"
    }
    dashboard_add $d bApply button gMan
    dashboard_set_property $d bApply text "应用"
    dashboard_set_property $d bApply onClick "apply_manual $d"

    dashboard_add $d gSt group self
    dashboard_set_property $d gSt title "板卡状态"
    dashboard_set_property $d gSt itemsPerRow 2
    dashboard_add $d bPoll button gSt
    dashboard_set_property $d bPoll text "读取状态"
    dashboard_set_property $d bPoll onClick "poll_status $d"
    dashboard_add $d lbSt label gSt
    dashboard_set_property $d lbSt text "(未读取)"

    dashboard_set_property $d self visible true
    puts "Dashboard 已打开: 窗口标题 MSA-2020 LED 控制台"
    return $d
}

proc apply_manual {d} {
    set v 0
    for {set i 0} {$i <= 8} {incr i} {
        if {[dashboard_get_property $d cb$i checked]} {
            set v [expr {$v | (1 << $i)}]
        }
    }
    led::manual $v
}

proc poll_status {d} {
    set bits [led::status]
    set s ""
    for {set i 8} {$i >= 0} {incr i -1} {
        append s [expr {(($bits >> $i) & 1) ? "●" : "○"}]
    }
    dashboard_set_property $d lbSt text "LED8→0: $s"
}

# ---------------------- 启动 ----------------------
if {[catch {led::connect} err]} {
    puts "连接失败: $err"
    puts "修复后手动执行: led::connect"
}
if {[catch {build_dashboard} err]} {
    puts "Dashboard 创建失败 ($err), 可改用命令行: led::mode N / led::manual V / led::status"
}
