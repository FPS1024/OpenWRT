# OpenWrt overlay — OrangePi 3 LTS (Allwinner H6)

把本仓库当作 **OpenWrt 24.10 的差分 overlay**：`overlay/` 里的文件按 OpenWrt 源码树
的相同路径覆盖上去，就得到带 OrangePi 3 LTS 板级支持 + UWE5622 Wi-Fi 驱动的构建树。
OpenWrt 源码固定到 commit `58584c6f2829a7e5d77376ab68aae3dcc4a392d8`，驱动源也固定到
`armbian/uwe5622` 的明确 commit，避免上游分支变化导致同一项目突然无法编译。

> ⚠️ **不要在 2 核 2G 的小机器上编译**（本项目的服务器就是因此假死重启过两次）。
> 建议 ≥4 核 / ≥8G 内存 / ≥25G 空闲磁盘。

## 内容

```
overlay/
  target/linux/sunxi/patches-6.6/460-arm64-dts-allwinner-add-orangepi-3-lts.patch # DTS 源码
  target/linux/sunxi/image/cortexa53.mk                     # 新增 xunlong_orangepi-3-lts 设备
  target/linux/sunxi/base-files/etc/board.d/02_network      # eth0 -> WAN
  target/linux/sunxi/base-files/etc/uci-defaults/99-opi3lts # br-lan/WAN network setup
  package/kernel/uwe5622/                                   # sprdwl_ng 驱动（含 OpenWrt backport 补丁）
  package/firmware/uwe5622-firmware/                        # UWE5622 固件
  package/boot/uboot-sunxi/                                 # 提供预编译 SPL/U-Boot 和 H6 启动环境
```

## 方案 A1 — GitHub Actions（推荐，零本机负担）

1. 在 GitHub 新建一个仓库，把本目录推上去（`main` 分支）。
2. 进仓库 **Actions → Build OpenWrt for Orange Pi 3 LTS → Run workflow**。
3. 跑完在 **Artifacts** 下载 `openwrt-opi3lts`（含 `*.img.gz`）。

## 方案 A2 — 任意一台大机器

```sh
sh scripts/build.sh
# 产物: .work/openwrt/bin/targets/sunxi/cortexa53/openwrt-*.img.gz
```

本地构建目录 `.work/openwrt` 会保留。再次运行同一命令时，OpenWrt 的依赖和 stamp 会复用已经完成的 toolchain、内核、UWE5622 驱动及其他包，只重建配置或源码确实变更的部分；不要删除 `.work/openwrt`，也不要运行 `make clean` / `make dirclean`。如果已有一个 OpenWrt 源码/构建目录，直接指定它来复用：

```sh
# 在项目仓库根目录执行；这里的 ow 是已有的 OpenWrt 源码/构建目录
OPENWRT_DIR="$PWD/ow" JOBS="$(nproc)" sh scripts/build.sh
```

如果没有现成的 OpenWrt 构建目录，直接运行 `sh scripts/build.sh`；脚本会在 `.work/openwrt` 创建并保留它。第一次仍需完整编译，后续继续用同一命令即可增量构建，不需要另写脚本。GitHub-hosted runner 每次是新环境，和本地复用目录不同。

## 方案 A3 — 临时租一台大 VPS

随便租一台 ≥4C8G 的按量机器，`git clone` 本仓库后执行 `sh scripts/build.sh` 即可，完事删机器。

## 烧写

```sh
gunzip -k openwrt-sunxi-cortexa53-xunlong_orangepi-3-lts-sdcard.img.gz
dd if=... .img of=/dev/sdX bs=1M conv=fsync    # sdX = SD 卡，别写错！
```

镜像里已经：
- 直接使用仓库中的 SPL/U-Boot 二进制和 H6 启动环境生成 SD 卡镜像；SPL 写入偏移为 8KB（sector 16）；
- 用**校准过的 DTS**（PMIC 走 r_i2c、Motorcomm PHY、rgmii-id、Wi-Fi SDIO 等）。

## 首次启动后的网络

- `eth0` = **WAN**（DHCP，插网线）
- `br-lan` = **192.168.8.1**，Wi-Fi 客户端默认从 `192.168.8.100` 起通过 DHCP 获取地址
- Wi-Fi 默认开启 **2.4 GHz / 信道 6 / HT20**，SSID `OrangePi-3-LTS`，WPA2-PSK 密码 `orangepi@7`
- 内置 LuCI 和 uhttpd，连上 Wi-Fi 后可访问 `http://192.168.8.1` 管理路由器

上述 Wi-Fi 密码是所有用户共用的公开默认值。部署后建议尽快换成自己的密码。设备不会设置固定的 root 管理密码；首次通过串口登录后运行 `passwd` 设置。
设置 root 密码后，再登录 LuCI；LuCI 使用 root 管理员账号。

用户可以随时通过 UCI 修改无线名称、密码和 2.4 GHz 信道，例如：

```sh
uci set wireless.default_radio0.ssid='自己的 Wi-Fi 名称'
uci set wireless.default_radio0.key='自己的 Wi-Fi 密码'
uci set wireless.radio0.channel='11'
uci commit wireless
wifi reload
```

首次启动时，驱动启动脚本会创建上述默认 AP；已有无线配置会保留，不会在之后每次启动时覆盖用户设置。默认不创建 monitor 虚拟接口。

## 设备树说明

仓库包含的是 Linux DTS 源码补丁，不包含预编译的 39 KB DTB。DTS 会随目标内核编译，构建出的
DTB 被打包进固件；具体 DTB 文件大小由内核编译结果决定。当前工作目录里没有单独提交 39 KB 的
DTB 文件。

## 无线验收

Actions 会先单独编译 UWE5622 驱动包，并检查最终镜像及固件包是否生成。这只能证明驱动通过编译，
不能代替实机验证。首次刷机后还需通过串口/有线确认 SDIO 设备识别、模块加载、`iw list` AP 能力、
手机连接与 DHCP、WAN 出口，以及重启后的 AP 恢复情况。
