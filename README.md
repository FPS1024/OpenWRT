# Orange Pi 3 LTS · OpenWrt AP Router

Builds OpenWrt 25.12.6 (Linux 6.12) for the Allwinner H6-based Orange Pi 3 LTS, including the board DTS, the UWE5622 Wi-Fi driver, a default AP, the LuCI web admin, the Argon theme and a Simplified Chinese UI. The OpenWrt source is pinned to [`64900e7`](https://github.com/openwrt/openwrt/commit/64900e756efa667774214f9c6b17c113222e01f7).

Wi-Fi has been verified on real Orange Pi 3 LTS hardware: a phone can join the AP, obtain an address and reach the internet through the wired WAN. Driver adaptation details and troubleshooting are in the [Wi-Fi driver notes](README-WIFI.md).

## Default network

| Item | Default |
| --- | --- |
| WAN | `eth0`, DHCP client |
| Router address | `192.168.8.1/24` |
| LAN DHCP pool | From `192.168.8.100` |
| Wi-Fi | 2.4 GHz, channel 6, HT20, WPA2-PSK |
| SSID / password | `OrangePi-3-LTS` / `orangepi@7` |
| LuCI | `http://192.168.8.1`, Argon theme and Simplified Chinese by default |

The Wi-Fi password is a public initial value; change it immediately after deployment. No root password is preset; on first boot run `passwd` over the serial console, then log in to LuCI. The current build scripts select LuCI/uhttpd; older images do not gain the web UI automatically and require a newly built image.

## Docker

The image bundles Docker (`dockerd`, `containerd`, `runc`, `docker compose` and LuCI Dockerman). On first boot, `99-opi3lts` writes the Docker defaults for the image layout:

| Item | Default |
| --- | --- |
| Data directory | The squashfs image uses `/overlay/docker` (a real f2fs mount, giving overlay2 a usable upperdir); the ext4 image keeps `/opt/docker/`. If the filesystem does not support overlay2, Docker falls back to vfs |
| Container DNS | The LAN address (default `192.168.8.1`) through the router's dnsmasq; otherwise the default bridge falls back to the unreachable `8.8.8.8` |
| fw4 forwarding | `docker -> wan`, written by the dockerd init so plain bridge containers can reach the internet |

If you change the LAN address, update `dns` in `/etc/config/dockerd` accordingly and restart dockerd.

The firmware does not preset any third-party registry mirror. If Docker Hub is unreachable directly, configure `registry_mirrors` in `/etc/config/dockerd` yourself.

User-defined Docker Compose networks (`br-xxxx`) are not in the `docker` zone. To allow outbound traffic, add the interface to the firewall or give that container host networking.

When a single service needs to bypass the Docker bridge, use `--network host`; the firmware neither presets nor auto-starts any workload container.

## Build

Ubuntu x86-64 is recommended, with at least 4 cores, 8 GB of RAM and 25 GB of free disk. The first build takes a while; keep the build directory so OpenWrt can reuse the unchanged toolchain, kernel and packages.

```sh
# From the repository root; the first run creates and keeps .work/openwrt
sh scripts/build.sh

# Reuse an existing OpenWrt build directory
OPENWRT_DIR="$PWD/ow" JOBS="$(nproc)" sh scripts/build.sh
```

`OPENWRT_DIR` is the build directory. The script resets tracked OpenWrt files that were modified, checks out the pinned source revision and reapplies this repository's `overlay/`, so keep custom changes in `overlay/`.

You can also push to `main` or manually run **Build OpenWrt for Orange Pi 3 LTS** in GitHub Actions. When it succeeds, open the **Artifacts** section at the bottom of the workflow run and download `openwrt-opi3lts`. The archive contains the flashable image, the manifest, checksums and the Wi-Fi driver packages; build logs are in the separate `build-diagnostics` artifact. Local and CI images are written to `bin/targets/sunxi/cortexa53/` and include both ext4 and squashfs SD-card images.

The default production GitHub Actions build does not compile target-side GCC, binutils, Git or Make, so it does not spend extra time on development tools. Set `include_dev_tools` to true when manually running the workflow, or use `INCLUDE_DEV_TOOLS=1 sh scripts/build.sh` locally, to add them to the firmware. Build logs are saved by stage as `package-compile`, `package-install`, `target-install` and `package-index`; `target-install` is the short stage that actually creates the images.

The firmware enables the official `packages` and LuCI feeds. The factory image includes the Argon theme, the Argon settings page and its Chinese package, plus Simplified Chinese translations for the LuCI base, firewall and package manager pages. `dnsmasq-full`, `libnettle8`, `libnetfilter-conntrack3`, `bash`, `curl`, `ip-full`, `ruby`, `ruby-yaml` and `unzip` are built into the image; `kmod-tun`, `kmod-inet-diag`, `kmod-nft-tproxy` and `kmod-nf-conntrack-netlink` match the current kernel. Ruby YJIT is disabled at build time to avoid compiling a full rustc/LLVM toolchain. The default production image also includes `sfdisk`, `partx-utils`, `losetup` and `resize2fs`. Node.js is not included; install it from the feed if needed (the official openwrt-25.12 feed provides Node 22; the Node 24 package definition under `overlay/feeds/packages/lang/node` is kept but no longer selected by default). The development image additionally provides `git`, `git-http`, `make`, `gcc` and `binutils`. OpenWrt has no target packages named `cmake` or Debian `build-essential`, so no invalid configuration is written; target-side build tools come from GCC, binutils and make. Argon is built from upstream sources and included directly; the official LuCI feed does not host Argon packages.

On first boot, the SD-card image runs `opi3lts-expand-storage`. The script reads the root filesystem's device number from `/proc/self/mountinfo`, resolves the root partition and its parent disk through `/sys/dev/block`, so it does not depend on `/dev/root` (procd replaces `/dev` with a new tmpfs and only creates nodes from sysfs) and does not hard-code device names; only when that lookup fails does it fall back to scanning the partition by the `root=PARTUUID` partition number. The preinit stage grows the partition before `mount_root`. When the root partition is in use and the kernel cannot re-read the partition table, the script first verifies that the on-disk table already reaches the end of the card, then reboots once so the next boot reads the new table; first boot may therefore reboot automatically. After the system mounts the overlay, the S99 stage grows the ext4/f2fs filesystem. The squashfs image grows its writable overlay; the ext4 image grows the root filesystem directly. It only writes `/etc/opi3lts-storage-expanded` after confirming that the root partition really fills the card, so an accidental empty expansion cannot be marked "done" and permanently disable growth. The image itself stays small; a multi-gigabyte squashfs is not the way to solve free space. After writing the image to cards of different capacities with balenaEtcher or `dd`, verify the expansion with:

```sh
logread -e opi3lts-expand-storage
cat /proc/partitions
df -h
ls -l /etc/opi3lts-storage-expanded
```

GitHub Actions can optionally send build-result email. Go to the repository's **Settings → Secrets and variables → Actions** and add `SMTP_USERNAME` and `SMTP_PASSWORD`; the default server is Outlook.com's `smtp-mail.outlook.com:587`, and an optional `SMTP_SERVER` can override it. Outlook usually requires SMTP AUTH or an app password. Without the secrets, only the notification is skipped and the build result is unaffected. After flashing, run `apk update` to install other userland software and avoid reinstalling the dependencies already built into the image from the rolling snapshot feed.

## Flashing

Extract the downloaded `.img.gz`, confirm that `/dev/sdX` is the SD-card device, then write it (balenaEtcher or a similar tool also works; the image expands to fill the card on first boot):

```sh
gunzip -k openwrt-sunxi-cortexa53-xunlong_orangepi-3-lts-squashfs-sdcard.img.gz
sudo dd if=openwrt-sunxi-cortexa53-xunlong_orangepi-3-lts-squashfs-sdcard.img \
  of=/dev/sdX bs=4M status=progress conv=fsync
```

**Writing to the wrong device destroys its data.** The image uses this repository's SPL/U-Boot and the Orange Pi 3 LTS-specific device tree.

## Changing Wi-Fi

Use **Network → Wireless** in LuCI, or UCI over SSH/serial:

```sh
uci set wireless.default_radio0.ssid='SSID'
uci set wireless.default_radio0.key='password'
uci commit wireless
wifi reload
```

On first boot the driver service creates the default wireless configuration; existing user settings are preserved afterwards. It is recommended to reboot before putting the device into service.
