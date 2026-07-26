# mqnic 插入主机 PCIe 槽后的验证

## ⚠️ 先说两个必须知道的前提

1. **现在还不能说"可以正常使用"。** mqnic 的 `.sof` **编译通过了**,但:
   - 台面 JTAG 烧录目前卡在配置("Device is in configuration state",大型
     PCIe 设计的配置问题,见下"烧录"一节);
   - 从没成功枚举/跑起来过。
   所以严格说,现在是"**编译好、待验证**"。

2. **★ mqnic 没有 Windows 驱动 ★。** Corundum 的驱动是 **Linux 内核模块**
   (`modules/mqnic/`,`.c`+Makefile),外加 Linux 用户态工具(`utils/`)。
   **没有 `.inf`/`.sys`,Windows 上无法把它当网卡用。**
   - Windows 主机:**只能看到 PCIe 设备被枚举**(设备管理器里一个未知设备,
     厂商 `VEN_1234` 设备 `DEV_1001`),但**装不了驱动、当不了网卡**。
   - 要真正当 100G 网卡用,**必须 Linux 主机**。

> 本设计的 PCIe 配置空间 = **Vendor 0x1234 / Device 0x1001**(mqnic 驱动认这个 ID)。

---

## A. 烧录(前置,两条路)

台面 JTAG 直烧大型 PCIe 设计现在会失败。装进主机槽后有两种烧法:

1. **JTAG 在槽内烧**(板子插主机槽 + JTAG 线还接着):
   ```
   H:\fpga\quartus\bin64\quartus_pgm -c 1 -m jtag -o "p;output_files/qsfp_mqnic.sof"
   ```
   注意:主机开机后 PCIe 会枚举,烧录后主机需要**重新扫描 PCIe 或重启**才认新设备。
   若仍报 configuration state,先让主机保持关机/复位,烧完再上电。

2. **烧进板载配置 Flash**(推荐,上电自动加载,PCIe 100ms 内就绪):
   把 `.sof` 转成 `.pof`/`.jic`(需知道板载 flash 型号),再烧 flash:
   ```
   H:\fpga\quartus\bin64\quartus_pfg -c qsfp_mqnic.sof qsfp_mqnic.jic ^
     -o device=<flash型号> -o mode=ASx4
   ```
   (flash 型号见 A-2020 手册;这条能绕开"配置期与主机 PCIe 抢时序"的问题。)

---

## B. Windows 主机 —— 只能验证枚举(当不了网卡)

板子插槽 + 烧好 + 主机重启后:

1. **设备管理器**:出现一个"其他设备 / 未知设备"。右键→属性→详细信息→
   硬件 ID,应看到 `PCI\VEN_1234&DEV_1001`。**看到 = PCIe 链路 + 枚举成功**
   (证明 FPGA 的 PCIe 硬核跑起来了)。
2. 命令行核对(PowerShell):
   ```powershell
   Get-PnpDevice -PresentOnly | Where-Object InstanceId -match "VEN_1234&DEV_1001"
   ```
   或看 BAR/链路:
   ```powershell
   Get-PnpDevice -Class System | ForEach-Object { $_.InstanceId } | Select-String "1234"
   ```
3. **到此为止。** Windows 没有 mqnic 驱动,黄色感叹号(无驱动)是正常的,
   装不上、也当不了网卡。想用网卡功能 → 转 Linux 主机(下节)。

---

## C. Linux 主机 —— 真正当 100G 网卡用

在装了这块板的 Linux 主机上:

1. **确认枚举**:
   ```bash
   lspci -d 1234:1001 -vvv        # 应列出设备 + BAR + 链路速率/宽度(Gen3 x16)
   ```
2. **编译 + 加载驱动**(内核头文件要装好):
   ```bash
   cd corundum/modules/mqnic
   make
   sudo insmod mqnic.ko            # 或 make install; modprobe mqnic
   dmesg | tail -30               # 看 mqnic probe 日志, 网口是否创建
   ```
3. **看网卡**:
   ```bash
   ip link                        # 出现 mqnic 的网口 (如 enp1s0 / eth?)
   ethtool <iface>                # 看速率/链路
   ```
4. **用户态工具**(诊断/固件信息):
   ```bash
   cd corundum/utils && make
   sudo ./mqnic-dump -d /dev/mqnic0        # 打印板卡/固件信息
   sudo ./mqnic-fw   -d /dev/mqnic0        # 固件/flash 相关
   ```
5. **配 IP + 通信**:
   ```bash
   sudo ip addr add 192.168.1.1/24 dev <iface>
   sudo ip link set <iface> up
   # QSFP0 接对端(或环回模块), ping 对端
   ```

> 注:Corundum 是 25G-per-lane。QSFP0 的 4 条 lane = 最多 4 个 25G 网口
> (聚合 100G 带宽),取决于固件里 IF_COUNT/PORT 配置(本移植 IF_COUNT=2)。

---

## 现实建议

- **想立刻验证"PCIe 枚举成功"**:Windows 主机看设备管理器出现 `VEN_1234&DEV_1001`
  即可(这一步能证明阶段4 的 PCIe 硬核+移植是通的)。
- **想真正跑网卡**:准备一台 **Linux 主机**,按 C 节走。
- **烧录**:强烈建议走 **板载 flash(.jic)** 方式,避开台面 JTAG 直烧大型 PCIe
  设计的配置时序问题。需要我帮你把 `.sof`→`.jic` 的 flash 型号/命令配好的话告诉我。
