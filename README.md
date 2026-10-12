# Orange Pi 3 LTS · OpenWrt AP 路由器

为全志 H6 的 Orange Pi 3 LTS 构建 OpenWrt 24.10（Linux 6.6），包含板级 DTS、UWE5622 Wi-Fi 驱动、默认 AP、LuCI 网页管理、Argon 主题和简体中文界面。OpenWrt 源码固定在 [`58584c6`](https://github.com/openwrt/openwrt/commit/58584c6f2829a7e5d77376ab68aae3dcc4a392d8)。

Wi-Fi 已在 Orange Pi 3 LTS 实机上验证：手机可连接 AP、获取地址并通过有线 WAN 上网。驱动适配细节和排错步骤见 [Wi-Fi 驱动适配说明](README-WIFI.md)。

## 默认网络

| 项目 | 默认值 |
| --- | --- |
| WAN | `eth0`，DHCP 客户端 |
| 路由器地址 | `192.168.8.1/24` |
| LAN DHCP 地址池 | `192.168.8.100` 起 |
| Wi-Fi | 2.4 GHz，信道 6，HT20，WPA2-PSK |
| SSID / 密码 | `OrangePi-3-LTS` / `orangepi@7` |
| LuCI | `http://192.168.8.1`，默认 Argon 主题和简体中文 |

Wi-Fi 密码是公开的初始值，部署后请立即修改。设备不预设 root 管理密码；首次启动通过串口运行 `passwd`，再登录 LuCI。当前构建脚本已选择 LuCI/uhttpd；已有的旧镜像不会因此自动获得网页管理，需刷入新的成功构建镜像。

## 构建

推荐使用 Ubuntu x86-64，至少 4 核、8 GB 内存和 25 GB 可用磁盘。首次构建耗时较长；保留构建目录，之后 OpenWrt 会复用未变化的工具链、内核和软件包。

```sh
# 在仓库根目录；第一次使用时会创建并保留 .work/openwrt
sh scripts/build.sh

# 已有 OpenWrt 构建目录时复用它
OPENWRT_DIR="$PWD/ow" JOBS="$(nproc)" sh scripts/build.sh
```

也可推送到 `main` 或在 GitHub Actions 手动运行 **Build OpenWrt for Orange Pi 3 LTS**。成功后打开该次 workflow run 页面底部的 **Artifacts**，下载 `openwrt-opi3lts`。压缩包包含刷机镜像、manifest、校验文件和 Wi-Fi 驱动包；构建日志在单独的 `build-diagnostics` artifact 中。本地和 CI 的镜像位于 `bin/targets/sunxi/cortexa53/`，包含 ext4 与 squashfs SD 卡镜像。

固件启用了官方 `packages` 和 LuCI 软件源，出厂包含 Argon 主题、Argon 设置页及其中文包，以及 LuCI 基础、Firewall 和软件包管理页面的简体中文翻译。`dnsmasq-full`、`libnettle8`、`libnetfilter-conntrack3` 以及 OpenClash 常用的 `bash`、`curl`、`ip-full`、`ruby`、`ruby-yaml` 和 `unzip` 直接编入镜像；`kmod-tun`、`kmod-inet-diag`、`kmod-nft-tproxy` 和 `kmod-nf-conntrack-netlink` 与当前内核匹配。维护工具还包含 `git`、`git-http`、`make`、`gcc`、`binutils`、`sfdisk`、`partx-utils`、`losetup` 和 `resize2fs`。OpenWrt 目标软件包中没有名为 `cmake` 或 Debian `build-essential` 的包，因此不会写入无效的配置项；目标端的编译工具由 GCC、binutils 和 make 提供。Argon 来自上游源码并直接编入固件；官方 LuCI 软件源不托管 Argon 包。

构建时会从 OpenClash 最新 GitHub Release 选择 nftables 可用的 LuCI IPK，并在依赖已经选入镜像后编入固件。Release API 或 IPK 下载失败时只跳过 OpenClash，保留其他固件构建；依赖包仍会作为必选项校验。也可以把 `luci-app-openclash*.ipk` 放入仓库根目录的 `apps/` 目录，作为本地或无网络构建的回退包。

SD 卡镜像首次启动会运行 `opi3lts-expand-storage`：把第二分区扩展到 SD/eMMC 卡尾部，并扩展 squashfs 的可写 overlay。这样用 balenaEtcher 或 `dd` 写入不同容量的卡后，系统会在第一次启动后使用剩余空间；扩容完成后会留下 `/etc/opi3lts-storage-expanded` 标记。

GitHub Actions 可选发送构建通知邮件。到仓库 **Settings → Secrets and variables → Actions** 添加 `SMTP_USERNAME` 和 `SMTP_PASSWORD`；默认使用 Outlook.com 的 `smtp-mail.outlook.com:587`，也可以添加可选的 `SMTP_SERVER` 覆盖服务器地址。Outlook 通常需要启用 SMTP AUTH 或使用应用专用密码。未配置 Secrets 时只跳过通知，不影响构建结果。刷机后可运行 `opkg update` 安装其他用户态软件，避免从滚动 Snapshot 源重复安装这些已内置依赖。

## 刷写

解压下载的 `.img.gz`，确认 `/dev/sdX` 是 SD 卡设备后写入：

```sh
gunzip -k openwrt-sunxi-cortexa53-xunlong_orangepi-3-lts-squashfs-sdcard.img.gz
sudo dd if=openwrt-sunxi-cortexa53-xunlong_orangepi-3-lts-squashfs-sdcard.img \
  of=/dev/sdX bs=4M status=progress conv=fsync
```

**写错设备会清除该设备上的数据。** 镜像使用本仓库的 SPL/U-Boot 和 Orange Pi 3 LTS 专用设备树。

## 修改 Wi-Fi

可在 LuCI 的 **Network → Wireless** 修改，也可通过 SSH/串口使用 UCI：

```sh
uci set wireless.default_radio0.ssid='SSID'
uci set wireless.default_radio0.key='password'
uci commit wireless
wifi reload
```

初次启动时驱动服务创建默认无线配置；之后会保留用户已有设置。
