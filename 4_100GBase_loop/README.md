# 4 100GBase_loop

**状态：🚧 开发中** —— 收发器环回、retimer 已**硬件验证**；bonded 100G MAC 板级受限。

QSFP0 100G-class 收发器点亮 + 环回验证。本项目是几个相关子工程的合集：

| 子目录 | 内容 | 状态 |
|--------|------|------|
| [xcvr/](xcvr/) | **QSFP0 4×25.78G GXT 收发器**，PCS PRBS31 内部串行环回 | ✅ **硬件验证**：ATX PLL 锁定 + 4 通道 PRBS31 全锁定零误码 |
| [retimer/](retimer/) | **DS250DF810 + FPC202** 经 I2C 上电初始化（为外部环回准备） | ✅ **硬件验证**：DS250/FPC202 初始化完成 |
| [mac_100g_bonded/](mac_100g_bonded/) | **bonded CAUI-4 100G MAC**（alt_e100s10 + 级联 ATX） | ⛔ 板级受限：越过 LC_PLL_MUX，卡 6-pack power_mode |
| [prbs_handbuilt_archive/](prbs_handbuilt_archive/) | 早期手搭 Native PHY PRBS（存档，未采用） | 📦 存档 |

## 关键结论：这块板的 QSFP0 天生是 4×25G

QSFP0 四条 lane 接到**非连续物理通道 0,1,3,4（跳过 ch2）** —— 这是为
**4×25G 独立 lane** 设计的（正是 `xcvr/` 已验证的用法，也是 Corundum/mqnic
的用法），**不是 bonded 100G**。所以：

- `xcvr/` 的 4×25.78G 独立通道环回 → 编译 + 硬件验证通过 ✅
- `mac_100g_bonded/` 的 bonded CAUI-4 → 卡在 6-pack power_mode：e100 把非连续
  的 ch0,1,3,4 绑成一组，未用的 ch2/ch5 必须 HIGH_PERF 才匹配，而板子接线
  决定了这做不到（连 Intel 自己的 example 都没有强制未用通道 power_mode 的
  assignment，因为标准板卡的 QSFP 都接连续通道）。
- **"100G 级"的天然路线 = 4×25G 聚合**（见 5 Corundum mqnic）。

## 收发器正解拓扑（xcvr/）

移植自 Corundum 520N_MX：master ATX(`atx_lcl`) + GXT 缓冲(`atx_blw`) +
4 个独立单通道 Native PHY + **iqclk** CDR refclk（单 refclk AD34 服务 4 通道），
`anlg_link=sr`（本板 1SG280LN2 短距才支持 25.78G），
master/buffer 时钟按物理三联组分配。详见 `xcvr/` 内说明与顶层 README。

## 用法

- `xcvr/`：烧 `output_files/qsfp_xcvr.sof`，跑 `python xcvr/xcvr_test.py`
  （读 ISSP 查各通道 PRBS 误码）。
- `retimer/`：烧 `output_files/retimer_init.sof`，跑 `python retimer/retimer_test.py`。
