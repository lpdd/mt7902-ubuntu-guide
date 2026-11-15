# Ubuntu 22.04（内核 6.8）下的 MediaTek MT7902 无线网卡配置指南

[English](README.md) | **简体中文**

本仓库记录在 Ubuntu 22.04 LTS（6.8 HWE 内核）上驱动 MediaTek MT7902
PCIe 无线网卡的完整步骤，使用已归档的
[`hmtheboy154/mt7902`](https://github.com/hmtheboy154/mt7902) 外部驱动，
并附带两个针对 6.8 内核的兼容补丁。

所需内容都来自公开、全球可访问的渠道：

* 驱动源码与固件：GitHub（`hmtheboy154/mt7902`）
* 编译器与内核头文件：Ubuntu 官方/本地镜像（`apt`）
* 补丁与脚本：本仓库

不需要账号、VPN 或特定地区的镜像。

## 实测环境

| 项目 | 值 |
|---|---|
| 系统 | Ubuntu 22.04 LTS（jammy），amd64 |
| 内核 | `6.8.0-40-generic`（HWE） |
| 网卡 | MediaTek MT7902 PCIe `[14c3:7902]` |
| 驱动 | `hmtheboy154/mt7902`，`backport` 分支，提交 `9d30262` |
| 编译器 | `gcc-12`（Ubuntu 12.3.0） |
| 接口名 | `wlp8s0` |

驱动自身声明支持 6.6–6.19 内核。本指南针对 6.8（Ubuntu 22.04 HWE）
以及在该内核上出现的两个失败点。

> **范围：** 仅 PCIe 版 MT7902；SDIO 版不受该驱动支持。6.12+ 内核建议
> 使用 [`morrownr/mt76`](https://github.com/morrownr/mt76)；Linux 7.1+
> 已原生支持 MT7902。

## 仓库内容

```
README.md                                        英文指南
README.zh-CN.md                                  本文件
patches/0001-mt76-define-rate-mask-flag.patch    编译修复（内核 < 6.12）
patches/0002-mt76-vif-phy-fallback-without-chanctx.patch
                                                 连接修复（内核 < 6.15）
patches/apply-patches.sh                         一键打两个补丁（可重复执行）
scripts/install.sh                               一键：克隆、打补丁、编译、安装
```

## 依赖

* Ubuntu 22.04，内核 6.6–6.19（本指南针对 6.8 HWE）。
* `sudo` 权限。
* 联网，或按[附录](#离线机器附录)准备离线安装包。

### 安装工具链

```bash
sudo apt update
sudo apt install -y git build-essential gcc-12 patch "linux-headers-$(uname -r)"
```

说明：

* Ubuntu 的 6.8 HWE 内核是用 **gcc-12** 编译的，外部模块也必须用
  `gcc-12`，否则会报 `/bin/sh: 1: gcc-12: not found`。`gcc-12` 位于
  `universe` 组件；标准桌面版默认已启用，如未启用：

  ```bash
  sudo add-apt-repository universe && sudo apt update
  ```

* 如果 `linux-headers-$(uname -r)` 找不到候选包，安装 HWE 头文件：

  ```bash
  sudo apt install -y linux-headers-generic-hwe-22.04
  ```

* 验证：`gcc-12 --version` 和 `ls /lib/modules/$(uname -r)/build`。

## 快速开始

```bash
git clone https://github.com/lpdd/mt7902-ubuntu-guide.git
cd mt7902-ubuntu-guide
bash scripts/install.sh        # 克隆驱动、打补丁、编译、安装
sudo reboot
```

重启后正常连接 Wi-Fi 即可。

## 手动步骤

### 1. 确认网卡存在

```bash
lspci -nnk | grep -iA3 14c3
```

应能看到：

```
Network controller [0280]: MEDIATEK Corp. Device [14c3:7902]
```

### 2. 获取驱动源码

```bash
git clone https://github.com/hmtheboy154/mt7902.git
cd mt7902
git checkout 9d302626688709ebf27dda597fdbce274efecea1   # 实测提交
```

默认分支即 `backport`。

### 3. 应用补丁

```bash
bash /path/to/patches/apply-patches.sh .
```

或使用标准 `patch`：

```bash
patch -p1 < /path/to/patches/0001-mt76-define-rate-mask-flag.patch
patch -p1 < /path/to/patches/0002-mt76-vif-phy-fallback-without-chanctx.patch
```

脚本会检查是否已打过补丁，并把被修改的文件备份为 `*.bak`。

### 4. 编译并安装

```bash
sudo make CC=gcc-12 install -j"$(nproc)"   # 编译并安装 mt7902e.ko
sudo make install_fw                       # 安装两个固件文件
```

Makefile 会做：

* `install` → 安装到
  `/lib/modules/$(uname -r)/kernel/drivers/net/wireless/mediatek/mt7902e/`
  并执行 `depmod`
* `install_fw` → 复制 `WIFI_MT7902_patch_mcu_1_1_hdr.bin` 和
  `WIFI_RAM_CODE_MT7902_1.bin` 到 `/lib/firmware/mediatek/`

只编译不安装：`make CC=gcc-12 -j"$(nproc)"`。

### 5. 重启

模块会随 PCI ID `14c3:7902` 在开机时自动加载。不要在 NetworkManager
占用接口时尝试 `modprobe -r` 旧模块——可能卡死，重启最干净。

### 6. 验证

```bash
lspci -nnk | grep -iA3 14c3        # Kernel driver in use: mt7902e
nmcli device status                # 出现 wifi 设备，如 wlp8s0
sudo dmesg | grep -i mt7902
```

正常输出类似：

```
mt7902e 0000:08:00.0: ASIC revision: 79020000
mt7902e 0000:08:00.0: HW/SW Version: 0x8a108a10, Build Time: 20251212032046a
mt7902e 0000:08:00.0: WM Firmware Version: ____000000, Build Time: 20251212032127
mt7902e 0000:08:00.0 wlp8s0: renamed from wlan0
```

然后连接：

```bash
nmcli dev wifi list
nmcli dev wifi connect "你的SSID" password "你的密码"
```

或直接使用桌面右上角的网络菜单。连接后确认：

```bash
nmcli device status          # 应显示 connected（已连接）
ip addr show wlp8s0
ping -c3 1.1.1.1
```

## 两个补丁说明

### 0001 —— 让内核 < 6.12 能编译

`src/scan.c` 和 `src/tx.c` 使用了 Linux 6.12 才加入 mac80211 的
`IEEE80211_TX_CTRL_DONT_USE_RATE_MASK`。在 6.8 上编译会报：

```
error: 'IEEE80211_TX_CTRL_DONT_USE_RATE_MASK' undeclared
```

补丁在 `src/mt76.h` 中把它定义为 `0`（6.12 之前的旧行为），
外层是 `#ifndef`，新内核上无副作用。

### 0002 —— 修复 `failed to insert STA entry for the AP (error -22)`

在 6.8 上装好驱动后，能扫描、能出现 Wi-Fi 列表，但连接任何网络都失败：

```
wlp8s0: failed to insert STA entry for the AP (error -22)
NetworkManager: Activation: (wifi) association took too long, failing activation
NetworkManager: state change: config -> failed (reason 'ssid-not-found')
```

这个错误发生在**校验 WPA 密码之前**，所以不是密码或热点的问题。原因链：

1. 驱动自带的 MT7902 固件（build `20251212032127`）feature 字段为
   `0x00`，**不支持 CNM**（channel context management / chanctx）。
2. 因此 `mt792x_get_mac80211_ops()` 把
   `add/remove/change/assign/unassign_vif_chanctx` 全部置空。
3. 6.8 的 mac80211 要求这 5 个回调“全有或全无”；全无时以
   `use_chanctx = false` 运行，永远不会调用 `assign_vif_chanctx`，
   驱动的 `mt76_vif_link->ctx` 一直为 `NULL`。
4. 该驱动回移植自主线 mt76 7.1，而主线 `mt76_vif_phy()` 开头有：

   ```c
   if (!hw->wiphy->n_radio)
       return hw->priv;   /* 单射频设备直接用主 phy */
   ```

   回移植时这段被 `LINUX_VERSION_CODE >= 6.15` 包掉（旧内核没有
   `n_radio` 字段），6.8 上整段被编译掉，回退逻辑缺失。
5. `mt76_vif_phy()` 返回 `NULL` → `mt76_sta_state()` 返回
   `-EINVAL`（即 `-22`）→ mac80211 中止连接。

补丁为 < 6.15 内核补回等价回退：

```c
#if (LINUX_VERSION_CODE < KERNEL_VERSION(6, 15, 0))
	if (!mlink->ctx)
		return hw->priv;
#endif
```

本卡是单射频，使用主 phy 总是正确的。

### 需要打哪些补丁？

| 内核 | 0001 | 0002 |
|---|---|---|
| 6.6 – 6.11 | 需要 | 需要 |
| 6.12 – 6.14 | 不需要 | 需要 |
| 6.15+ | 不需要 | 不需要（主线回退已存在） |

两个都打在任何内核上都无害；条件编译会让不需要的部分自动失效。

## 故障排查

### 报 `gcc-12: not found`

```bash
sudo apt install gcc-12
sudo make CC=gcc-12 install -j"$(nproc)"
```

### 仍然出现 `failed to insert STA entry for the AP (error -22)`

确认加载的是**新**模块：

```bash
grep -n "Backport fix" src/mac80211.c     # 补丁 0002 已打
modinfo -n mt7902e                        # 当前模块路径
ls -l "$(modinfo -n mt7902e)"             # 时间应为本次编译时间
```

重新编译、安装后必须重启（`make install` 只是覆盖文件，正在运行的
模块不会变）。

### `modprobe -r mt7902e` 被杀死 / `Device or resource busy`

NetworkManager / wpa_supplicant 仍占用接口，卸载会卡住。直接重启，
模块开机自动加载。

### `module verification failed: signature and/or required key missing`

未签名外部模块的正常提示，内核被标记为 tainted，不是错误。

### `rfkill` 显示被禁用

```bash
rfkill list
sudo rfkill unblock wifi
```

### NetworkManager 报 `ssid-not-found`

这是“关联未完成”的笼统原因。先看 `dmesg`，真正的错误几乎总在那里。

### 能扫描但关联失败

失败后立刻执行 `sudo dmesg | tail -50`，把驱动错误发到 Issue。

### 蓝牙不可用

MT7902 蓝牙需要驱动的另一个分支：
[`bluetooth_backport`](https://github.com/hmtheboy154/mt7902/tree/bluetooth_backport)。
本指南只涉及 Wi-Fi。

### 其他内核 / 发行版

* 6.12+：[`morrownr/mt76`](https://github.com/morrownr/mt76) 是该回移植
  的维护版继任者。
* 7.1+：MT7902 Wi-Fi 与蓝牙已进入主线，优先使用发行版内核。

## 卸载

在驱动目录中：

```bash
sudo make uninstall       # 删除 mt7902e.ko 并执行 depmod
sudo make uninstall_fw    # 可选：删除两个固件文件
sudo reboot
```

## 离线机器（附录）

可在**相同 Ubuntu 版本、架构和内核版本**的联网机器上下载工具链：

```bash
mkdir -p debs && cd debs
apt-get download $(apt-cache depends --recurse --no-recommends \
  --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances \
  gcc-12 build-essential patch "linux-headers-$(uname -r)" \
  | grep '^\w' | sort -u)
```

如果联网机器的内核与目标机不同，请把 `"linux-headers-$(uname -r)"`
换成目标机的确切版本，例如
`linux-headers-6.8.0-40-generic linux-hwe-6.8-headers-6.8.0-40`。

把 `debs/` 和驱动源码（联网时 `git clone`，或从 GitHub 下载 tarball）
拷到目标机器，然后：

```bash
cd debs
sudo dpkg -i *.deb
sudo dpkg -i *.deb        # 第二遍：补齐第一遍未完成配置的包
sudo dpkg -C              # 检查遗留问题
```

固件随驱动仓库提供（`firmware/`），因此源码拷过去后
`sudo make install_fw` 完全可离线执行。

## 参考

* 驱动：<https://github.com/hmtheboy154/mt7902>（已归档）
* 主线 MT7902 补丁：<https://lore.kernel.org/all/20260219004007.19733-1-sean.wang@kernel.org/>
* 6.12+ 继任驱动：<https://github.com/morrownr/mt76>
* 自 linux-firmware 2026-03-09 起，MT7902 固件也已随发行版固件包提供
  （可检查本机 `linux-firmware` 版本）。

## 许可

驱动源码为 GPL-2.0。本仓库中的补丁与脚本为 GPL-2.0-only，全文见
[LICENSE](LICENSE)。

## 贡献

在其他 Ubuntu/内核组合上测试过？遇到别的失败情况？欢迎开 Issue，并附上：

* `lsb_release -ds`
* `uname -r`
* `lspci -nnk | grep -iA3 14c3`
* 相关的 `sudo dmesg | tail -50`
