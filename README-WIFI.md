# UWE5622 Wi-Fi Driver Notes

This document describes how the UNISOC UWE5622 (onboard AW859A Wi-Fi/BT combo module) is adapted to OpenWrt on the Orange Pi 3 LTS, including boot dependencies and real-hardware troubleshooting. This project validates Wi-Fi AP mode; Bluetooth is out of scope.

## Components

| Part | Implementation |
| --- | --- |
| Kernel | OpenWrt 25.12.6 pinned source, Linux 6.12 |
| Driver | `kmod-uwe5622`, from `armbian/uwe5622` commit `d6bec7538a0b4b67e35715ad71eaa056555524cb` |
| Modules | `uwe5622_bsp_sdio.ko` (SDIO/WCN bus) and `sprdwl_ng.ko` (cfg80211 Wi-Fi) |
| Firmware | `uwe5622-firmware`, installed to `/lib/firmware/uwe5622/` |
| Wireless stack | OpenWrt mac80211/cfg80211, hostapd, wifi-scripts |
| Board support | This project's Orange Pi 3 LTS DTS: `sun50i-h6-orangepi-3-lts.dts` |

The driver package source revision, kernel build arguments and patches are under `overlay/package/kernel/uwe5622/`; the firmware files and install rules are under `overlay/package/firmware/uwe5622-firmware/`.

## Device tree and SDIO power-up

UWE5622 is connected through the H6's **MMC1 / SDIO** bus. The device-tree patch is `overlay/target/linux/sunxi/patches-6.12/460-arm64-dts-allwinner-add-orangepi-3-lts.patch`; key settings include:

- `mmc1` is a 4-bit, non-removable SDIO device and references `wifi_pwrseq`.
- `vcc33-wifi` controls the Wi-Fi 3.3 V supply through PH7.
- The power sequence drives the active-low PM3 reset through `mmc-pwrseq-simple` and waits 200 ms after power-up.
- The power sequence needs the H6 RTC to provide the `CLK_OSC32K_FANOUT` external clock.

`scripts/apply-overlay.sh` therefore enables `CONFIG_RTC_CLASS=y` and `CONFIG_RTC_DRV_SUN6I=y` in the sunxi Cortex-A53 kernel configuration. Without the RTC clock provider the kernel reports `wifi-pwrseq: external clock not ready`, the device stays in `devices_deferred`, and MMC1 never enumerates the SDIO card. Fix the device tree/kernel clock dependency first; rebuilding the Wi-Fi module alone will not help.

Do not substitute the device tree of a regular Orange Pi 3 for the LTS tree. The LTS board's PMIC, GPIOs, power and wireless wiring must be handled by this project's `sun50i-h6-orangepi-3-lts.dts`.

## Driver patches and kernel API

The driver is an out-of-tree community kernel module and must be adapted to the Linux 6.12 and mac80211 backport provided by OpenWrt. The current patches mainly handle:

- cfg80211 backport API compatibility and passing external-module Kbuild configuration symbols.
- cfg80211/netdev locking and connect/roam state synchronization.
- Linux 6.12 changes to station/channel queries, station dump and variable-length arrays.
- Avoiding an accidental chip power-down when power saving is disabled.

Patches are stored in numeric order under `overlay/package/kernel/uwe5622/patches/`. Do not restore the old `080-cfg80211-set-wiphy-params-backport-radio-idx.patch`: the pinned OpenWrt cfg80211 callback expects a two-argument function, while that old patch forces a three-argument signature and fails to compile with `incompatible-pointer-types`.

The build must prepare the target kernel and mac80211 backport before compiling `package/kernel/uwe5622`. This project's scripts and Actions follow that order and check the final image manifest and the UWE5622 driver/firmware packages.

## Delayed loading and the default AP

The wireless hardware appears later than early boot, so the driver package does not use the kernel's automatic load list. `sprdwl-delay` is started by procd at a later stage; it waits, loads `uwe5622_bsp_sdio` and `sprdwl_ng` in order, and waits for the cfg80211 phy to appear. Once the phy is ready it runs `wifi config`, so OpenWrt does not miss the radio configuration while the wireless device is still absent.

On first radio discovery, `sprdwl-start` creates and enables the following AP; existing UCI wireless configuration is preserved:

- 2.4 GHz, channel 6, HT20
- SSID `OrangePi-3-LTS`
- WPA2-PSK, initial password `orangepi@7`
- AP attached to `lan`, LAN address `192.168.8.1/24`

The initial password is a public value and should be changed promptly. The startup script writes the current Wi-Fi password to the root-only file `/root/opi3lts-wifi-password` and does not log it to the system log.

2.4 GHz HT20 was chosen because AP mode, phone association and internet access have been verified on this board. A previously tested VHT80 configuration failed in the current hostapd because it does not recognize the `ieee80211ac` / `vht_*` options; this project does not claim 5 GHz VHT80 as verified.

Change SSID, password and channel through UCI:

```sh
uci set wireless.default_radio0.ssid='your-name'
uci set wireless.default_radio0.key='your-password-at-least-eight-characters'
uci set wireless.radio0.channel='11'
uci commit wireless
wifi reload
```

## Hardware verification

First check MMC/SDIO, the power sequence, the modules and the phy:

```sh
mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null || true
dmesg | grep -iE 'mmc1|wifi-pwrseq|uwe5622|sprd|sdio|firmware'
cat /sys/kernel/debug/devices_deferred
lsmod | grep -E 'uwe5622_bsp_sdio|sprdwl_ng'
iw dev
```

On a successful boot you should see MMC1 enumerate the SDIO card, the driver read the firmware/INI files under `/lib/firmware/uwe5622/`, and `iw dev` list the wireless phy. After the AP starts, check:

```sh
wifi status
iw dev
logread | grep -iE 'hostapd|AP-ENABLED|AP-STA|handshake|dhcp'
iwinfo phy0-ap0 assoclist
cat /tmp/dhcp.leases
```

Verified on real hardware: `phy0-ap0` is in AP mode, hostapd reports `AP-ENABLED`, the WPA four-way handshake completes, and the client obtains an address from the LAN DHCP server and reaches the internet through the `eth0` WAN. Repeat the checks after a reboot to confirm that the default configuration and delayed loading recover.

## Common failure modes

| Symptom | Check first |
| --- | --- |
| `wifi-pwrseq: external clock not ready`, no MMC1 | The DTS RTC external-clock reference; whether `RTC_CLASS` and `RTC_DRV_SUN6I` are in the effective kernel configuration; `devices_deferred` |
| MMC1 exists but the SDIO scan times out | PH7 power, PM3 reset, `mmc1` `vmmc/vqmmc` and `wifi_pwrseq`; this is enumeration/power-up, so start with hostapd only after it works |
| Modules are loaded but there is no phy | Whether MMC1 enumerated the card, SDIO probe and firmware-load messages in `dmesg`, and whether the driver service started after the device appeared |
| `iw dev` shows a phy but the wireless configuration is empty | Whether `wifi config` ran after the driver loaded; check `/etc/config/wireless` and `logread -e sprdwl-start` |
| hostapd reports `unknown configuration item` for VHT/11ac parameters | Use the verified 2.4 GHz, channel 6, HT20 configuration first |
| The phone associates but gets no IP | Whether the AP is attached to `lan`, whether `dhcp.lan.dhcpv4` is `server`, and whether `br-lan` has `192.168.8.1/24` |

This record reflects the current pinned source and the results from one Orange Pi 3 LTS. After changing the kernel, driver, wireless packages or DTS, rebuild and repeat the full hardware verification.
