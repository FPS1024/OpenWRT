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
  package/boot/uboot-sunxi/                                 # 生成启动脚本并暂存 Orange Pi 3 LTS U-Boot
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

## 方案 A3 — 临时租一台大 VPS

随便租一台 ≥4C8G 的按量机器，`git clone` 本仓库后执行 `sh scripts/build.sh` 即可，完事删机器。

## 烧写

```sh
gunzip -k openwrt-sunxi-cortexa53-xunlong_orangepi-3-lts-sdcard.img.gz
dd if=... .img of=/dev/sdX bs=1M conv=fsync    # sdX = SD 卡，别写错！
```

镜像里已经：
- 使用项目 U-Boot 包暂存的启动脚本和 bootloader（写入偏移 8KB / sector 16）；
- 用**校准过的 DTS**（PMIC 走 r_i2c、Motorcomm PHY、rgmii-id、Wi-Fi SDIO 等）。

## 首次启动后的网络

- `eth0` = **WAN**（DHCP，插网线）
- `br-lan` = **192.168.8.1**，Wi-Fi AP `OpenWrt-3LTS`

首次启动后会生成随机 Wi-Fi 密码，保存在设备 `/root/opi3lts-wifi-password`（权限为仅 root 可读）。
可通过串口控制台读取。SSID 默认是 `OpenWrt-3LTS`；之后可通过 `uci` 修改，
启动脚本只补全缺失的无线设置，不覆盖已有配置。默认不创建 monitor 虚拟接口。

## 设备树说明

仓库包含的是 Linux DTS 源码补丁，不包含预编译的 39 KB DTB。DTS 会随目标内核编译，构建出的
DTB 被打包进固件；具体 DTB 文件大小由内核编译结果决定。当前工作目录里没有单独提交 39 KB 的
DTB 文件。

## 无线验收

Actions 会先单独编译 UWE5622 驱动包，并检查最终镜像及固件包是否生成。这只能证明驱动通过编译，
不能代替实机验证。首次刷机后还需通过串口/有线确认 SDIO 设备识别、模块加载、`iw list` AP 能力、
手机连接与 DHCP、WAN 出口，以及重启后的 AP 恢复情况。
