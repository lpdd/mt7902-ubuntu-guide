# MediaTek MT7902 Wi-Fi on Ubuntu 22.04 (kernel 6.8)

**English** | [简体中文](README.zh-CN.md)

A practical setup guide for the MediaTek MT7902 PCIe Wi-Fi card on Ubuntu
22.04 LTS with the 6.8 HWE kernel, using the (now archived)
[`hmtheboy154/mt7902`](https://github.com/hmtheboy154/mt7902) out-of-tree
driver, plus two small compatibility patches for kernel 6.8.

Everything needed can be downloaded from public sources:

* driver source and firmware: GitHub (`hmtheboy154/mt7902`)
* toolchain and kernel headers: your Ubuntu mirror (`apt`)
* patches and scripts: this repository

No account, VPN, or region-specific mirror is required.

## Tested on

| Item | Value |
|---|---|
| OS | Ubuntu 22.04 LTS (jammy), amd64 |
| Kernel | `6.8.0-40-generic` (HWE) |
| Wi-Fi card | MediaTek MT7902 PCIe `[14c3:7902]` |
| Driver | `hmtheboy154/mt7902`, branch `backport`, commit `9d30262` |
| Compiler | `gcc-12` (Ubuntu 12.3.0) |
| Interface | `wlp8s0` |

The driver itself claims kernel support 6.6–6.19. This guide covers the 6.8
case (Ubuntu 22.04 HWE) and the two failure modes that occur there.

> **Scope:** PCIe MT7902 only. The SDIO variant is not supported by this
> driver. For kernel 6.12+ consider
> [`morrownr/mt76`](https://github.com/morrownr/mt76); Linux 7.1+ has
> in-tree MT7902 support.

## Repository contents

```
README.md                                        this guide
README.zh-CN.md                                  Chinese translation
patches/0001-mt76-define-rate-mask-flag.patch    compile fix for kernels < 6.12
patches/0002-mt76-vif-phy-fallback-without-chanctx.patch
                                                 association fix for kernels < 6.15
patches/apply-patches.sh                         applies both patches (idempotent)
scripts/install.sh                               one-shot: clone, patch, build, install
```

## Requirements

* Ubuntu 22.04 with kernel 6.6–6.19 (6.8 HWE is what this guide targets).
* Root access (`sudo`).
* Either internet access, or the offline package set described in the
  [appendix](#offline-machines-appendix).

### Install the toolchain

```bash
sudo apt update
sudo apt install -y git build-essential gcc-12 patch "linux-headers-$(uname -r)"
```

Notes:

* Ubuntu's 6.8 HWE kernel was built with **gcc-12**. Building an
  out-of-tree module against its headers requires `gcc-12`; otherwise the
  build fails with `/bin/sh: 1: gcc-12: not found`. `gcc-12` is in the
  `universe` component — on a standard desktop it is already enabled, if not:

  ```bash
  sudo add-apt-repository universe && sudo apt update
  ```

* If `linux-headers-$(uname -r)` has no candidate, install the HWE headers:

  ```bash
  sudo apt install -y linux-headers-generic-hwe-22.04
  ```

* Verify: `gcc-12 --version` and `ls /lib/modules/$(uname -r)/build`.

## Quick start

```bash
git clone https://github.com/lpdd/mt7902-ubuntu-guide.git
cd mt7902-ubuntu-guide
bash scripts/install.sh        # clones the driver, patches, builds, installs
sudo reboot
```

Then connect to Wi-Fi as usual.

## Manual steps

### 1. Check that the card is present

```bash
lspci -nnk | grep -iA3 14c3
```

Expected:

```
Network controller [0280]: MEDIATEK Corp. Device [14c3:7902]
```

### 2. Get the driver source

```bash
git clone https://github.com/hmtheboy154/mt7902.git
cd mt7902
git checkout 9d302626688709ebf27dda597fdbce274efecea1   # tested commit
```

The default branch is `backport`.

### 3. Apply the patches

```bash
bash /path/to/patches/apply-patches.sh .
```

or with plain `patch`:

```bash
patch -p1 < /path/to/patches/0001-mt76-define-rate-mask-flag.patch
patch -p1 < /path/to/patches/0002-mt76-vif-phy-fallback-without-chanctx.patch
```

The script checks for already-applied patches and backs up every file it
modifies (`*.bak`).

### 4. Build and install

```bash
sudo make CC=gcc-12 install -j"$(nproc)"   # builds and installs mt7902e.ko
sudo make install_fw                       # installs the two firmware files
```

What the Makefile does:

* `install` → `/lib/modules/$(uname -r)/kernel/drivers/net/wireless/mediatek/mt7902e/`
  then runs `depmod`
* `install_fw` → `/lib/firmware/mediatek/WIFI_MT7902_patch_mcu_1_1_hdr.bin`
  and `WIFI_RAM_CODE_MT7902_1.bin`

If you only want to compile: `make CC=gcc-12 -j"$(nproc)"`.

### 5. Reboot

The module is loaded automatically at boot (PCI ID `14c3:7902`). Do not try
to `modprobe -r` the old module while NetworkManager owns the interface —
it can hang; a reboot is the clean way.

### 6. Verify

```bash
lspci -nnk | grep -iA3 14c3        # Kernel driver in use: mt7902e
nmcli device status                # a wifi device, e.g. wlp8s0
sudo dmesg | grep -i mt7902
```

Healthy output looks like:

```
mt7902e 0000:08:00.0: ASIC revision: 79020000
mt7902e 0000:08:00.0: HW/SW Version: 0x8a108a10, Build Time: 20251212032046a
mt7902e 0000:08:00.0: WM Firmware Version: ____000000, Build Time: 20251212032127
mt7902e 0000:08:00.0 wlp8s0: renamed from wlan0
```

Then connect:

```bash
nmcli dev wifi list
nmcli dev wifi connect "YOUR-SSID" password "YOUR-PASSWORD"
```

or use the desktop network menu. After connecting:

```bash
nmcli device status          # should say connected
ip addr show wlp8s0
ping -c3 1.1.1.1
```

## The two patches

### 0001 — build on kernels older than 6.12

`src/scan.c` and `src/tx.c` use `IEEE80211_TX_CTRL_DONT_USE_RATE_MASK`,
which was added to mac80211 in Linux 6.12. Building on 6.8 fails with:

```
error: 'IEEE80211_TX_CTRL_DONT_USE_RATE_MASK' undeclared
```

The patch defines the flag as `0` (pre-6.12 behaviour) in `src/mt76.h`, so
the driver compiles and behaves like the 6.8 driver did before the flag
existed. It is wrapped in `#ifndef`, therefore harmless on newer kernels.

### 0002 — fix `failed to insert STA entry for the AP (error -22)`

Symptoms after installing the driver on kernel 6.8:

```
wlp8s0: failed to insert STA entry for the AP (error -22)
NetworkManager: Activation: (wifi) association took too long, failing activation
NetworkManager: state change: config -> failed (reason 'ssid-not-found')
```

This happens **before** the WPA password is checked, so it is not a
credentials or hotspot problem. Root cause:

1. The MT7902 firmware bundled with the driver (build `20251212032127`)
   advertises feature caps `0x00`, i.e. it does **not** support CNM
   (channel-context management / chanctx).
2. `mt792x_get_mac80211_ops()` therefore clears
   `add/remove/change/assign/unassign_vif_chanctx`.
3. Kernel 6.8's mac80211 requires either all five callbacks or none. With
   none it runs with `use_chanctx = false` and never calls
   `assign_vif_chanctx`, so the driver's `mt76_vif_link->ctx` stays `NULL`.
4. The backport is based on mainline mt76 7.1, where `mt76_vif_phy()`
   begins with:

   ```c
   if (!hw->wiphy->n_radio)
       return hw->priv;   /* single-radio device -> main phy */
   ```

   The backport compiles that out for kernels < 6.15 (`n_radio` does not
   exist there), so the fallback is missing on 6.8.
5. `mt76_vif_phy()` returns `NULL` → `mt76_sta_state()` returns `-EINVAL`
   (`-22`) → mac80211 aborts the connection.

The patch restores the equivalent fallback for kernels < 6.15:

```c
#if (LINUX_VERSION_CODE < KERNEL_VERSION(6, 15, 0))
	if (!mlink->ctx)
		return hw->priv;
#endif
```

The card is single-radio, so the main phy is always the right one.

### Which patches do I need?

| Kernel | 0001 | 0002 |
|---|---|---|
| 6.6 – 6.11 | yes | yes |
| 6.12 – 6.14 | no | yes |
| 6.15+ | no | no (upstream early return is present) |

Applying both on any kernel is harmless; the guards make them no-ops where
they are not needed.

## Troubleshooting

### `gcc-12: not found`

```bash
sudo apt install gcc-12
sudo make CC=gcc-12 install -j"$(nproc)"
```

### `failed to insert STA entry for the AP (error -22)` still appears

Make sure the **new** module is the one loaded:

```bash
grep -n "Backport fix" src/mac80211.c     # patch 0002 present
modinfo -n mt7902e                        # path of the loaded module
ls -l "$(modinfo -n mt7902e)"             # timestamp should be your build
```

Rebuild, reinstall, and reboot (`make install` copies the module on top of
the old one; the running module does not change until reboot).

### `modprobe -r mt7902e` is killed / `Device or resource busy`

NetworkManager/wpa_supplicant still own the interface, so unload blocks.
Just reboot; the module loads automatically at boot.

### `module verification failed: signature and/or required key missing`

Normal for unsigned out-of-tree modules; the kernel is tainted. Not an
error.

### `rfkill` shows the device blocked

```bash
rfkill list
sudo rfkill unblock wifi
```

### NetworkManager says `ssid-not-found`

This is a generic reason for "association did not complete". Check
`dmesg` first — the real error is almost always there.

### Scanning works but association fails

Run `sudo dmesg | tail -50` right after the attempt and look for the
driver error. Include it in a GitHub issue if the patches do not help.

### Bluetooth does not work

MT7902 Bluetooth needs a different branch of the driver:
[`bluetooth_backport`](https://github.com/hmtheboy154/mt7902/tree/bluetooth_backport).
This guide only covers Wi-Fi.

### Other kernels / distributions

* Kernel 6.12+: [`morrownr/mt76`](https://github.com/morrownr/mt76) is the
  maintained successor of this backport.
* Linux 7.1+: MT7902 Wi-Fi and Bluetooth are supported in-tree; prefer the
  distribution's kernel.

## Uninstall

From the driver directory:

```bash
sudo make uninstall       # removes mt7902e.ko and runs depmod
sudo make uninstall_fw    # optional: removes the two firmware files
sudo reboot
```

## Offline machines (appendix)

The toolchain can be downloaded on any machine with the **same Ubuntu
release, architecture and kernel version**. On the online machine:

```bash
mkdir -p debs && cd debs
apt-get download $(apt-cache depends --recurse --no-recommends \
  --no-suggests --no-conflicts --no-breaks --no-replaces --no-enhances \
  gcc-12 build-essential patch "linux-headers-$(uname -r)" \
  | grep '^\w' | sort -u)
```

If the online machine does not run the target kernel, replace
`"linux-headers-$(uname -r)"` with the exact target versions, e.g.
`linux-headers-6.8.0-40-generic linux-hwe-6.8-headers-6.8.0-40`.

Copy `debs/` and the driver source (clone it online, or download a tarball
from GitHub) to the target machine, then:

```bash
cd debs
sudo dpkg -i *.deb
sudo dpkg -i *.deb        # second pass: fixes packages that failed to configure
sudo dpkg -C              # check for remaining issues
```

The firmware is included in the driver repository (`firmware/`), so
`sudo make install_fw` works fully offline once the source is copied.

## Notes and references

* Driver: <https://github.com/hmtheboy154/mt7902> (archived)
* Upstream MT7902 patches: <https://lore.kernel.org/all/20260219004007.19733-1-sean.wang@kernel.org/>
* Successor for kernel 6.12+: <https://github.com/morrownr/mt76>
* Firmware is also shipped by `linux-firmware` since release 2026-03-09
  (check your distribution's package).

## License

The driver source is GPL-2.0. The patches and scripts in this repository
are GPL-2.0-only — see [LICENSE](LICENSE).

## Contributing

Tested on another Ubuntu/kernel combination? Found a different failure
mode? Please open an issue and include:

* `lsb_release -ds`
* `uname -r`
* `lspci -nnk | grep -iA3 14c3`
* the relevant `sudo dmesg | tail -50` lines
