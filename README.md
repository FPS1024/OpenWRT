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

Actions 的默认生产构建不编译设备端 GCC、binutils、Git 和 Make，因此不会为开发工具付出额外的长时间编译。手动运行 workflow 时把 `include_dev_tools` 设为 true，或本地使用 `INCLUDE_DEV_TOOLS=1 sh scripts/build.sh`，才会把这批工具放进固件。构建日志按 `package-compile`、`package-install`、`target-install` 和 `package-index` 分阶段保存；其中 `target-install` 是实际制作镜像的短阶段。

固件启用了官方 `packages` 和 LuCI 软件源，出厂包含 Argon 主题、Argon 设置页及其中文包，以及 LuCI 基础、Firewall 和软件包管理页面的简体中文翻译。`dnsmasq-full`、`libnettle8`、`libnetfilter-conntrack3` 以及 OpenClash 常用的 `bash`、`curl`、`ip-full`、`ruby`、`ruby-yaml` 和 `unzip` 直接编入镜像；`kmod-tun`、`kmod-inet-diag`、`kmod-nft-tproxy` 和 `kmod-nf-conntrack-netlink` 与当前内核匹配。默认生产镜像还包含 `sfdisk`、`partx-utils`、`losetup` 和 `resize2fs`，以及 **Node.js 24.21.0**（`node` 与 `node-npm`，small-icu 的 i18n 数据已直接打进二进制）。固定的 `openwrt-24.10` 软件源只提供 Node 20，因此包定义放在仓库的 `overlay/feeds/packages/lang/node`；Node 24 要求宿主机同时有 `gcc-12` 和 `g++-12`，本地构建由 `scripts/build.sh` 预检，CI 由 workflow 自行安装。从零编译 Node 约需五小时，而 CI 每次只缓存 `dl/`，所以带 Node 的 Actions 构建会接近六小时的作业上限。开发镜像额外提供 `git`、`git-http`、`make`、`gcc` 和 `binutils`。OpenWrt 目标软件包中没有名为 `cmake` 或 Debian `build-essential` 的包，因此不会写入无效的配置项；目标端的编译工具由 GCC、binutils 和 make 提供。Argon 来自上游源码并直接编入固件；官方 LuCI 软件源不托管 Argon 包。

为保持出厂系统稳定，固件只预装 OpenClash 运行依赖，不内置 OpenClash LuCI 插件。这样不会让插件页面代码在 LuCI 菜单初始化时影响整站可用性；需要使用时可在刷机后单独安装与当前 LuCI 兼容的 OpenClash 包。构建会检查关键依赖已进入镜像。

SD 卡镜像首次启动会运行 `opi3lts-expand-storage`。脚本用 `/proc/self/mountinfo` 里根文件系统的设备号，经 `/sys/dev/block` 反查根分区及其父磁盘，因此不依赖 `/dev/root`（procd 会把 `/dev` 换成新的 tmpfs，只按 sysfs 建节点），也不写死设备名；只有查不到时才回退到按 `root=PARTUUID` 的分区号扫描。preinit 阶段先在 `mount_root` 之前扩分区；根分区正在使用、内核无法重读分区表时，脚本会先校验盘上分区表已经到达卡尾，再重启一次，让下一次启动直接读到新分区表，所以首次启动可能自动重启一次。系统挂载 overlay 后，S99 阶段才扩展 ext4/f2fs 文件系统。squashfs 镜像会扩展其可写 overlay，ext4 镜像会直接扩展根文件系统。只有确认根分区真的占满整张卡之后才会写 `/etc/opi3lts-storage-expanded`，避免一次空扩容就被标记成"已完成"而永久禁用扩容。镜像本身仍保持小体积，不能靠制作 8GB 的 squashfs 解决空间问题。用 balenaEtcher 或 `dd` 写入不同容量的卡后，可用下面的命令确认扩容已经完成：

```sh
logread -e opi3lts-expand-storage
cat /proc/partitions
df -h
ls -l /etc/opi3lts-storage-expanded
```

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

初次启动时驱动服务创建默认无线配置；之后会保留用户已有设置,建议重启以后再投入使用。
