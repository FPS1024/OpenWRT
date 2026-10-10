#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
	echo "Usage: $0 OPENWRT_SOURCE_DIR" >&2
	exit 2
fi

HERE="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OW_DIR="$1"
KERNEL_CONFIG="$OW_DIR/target/linux/sunxi/config-6.6"

cp -a "$HERE/overlay/." "$OW_DIR/"

# Linux 6.6 receives a backport that makes REALTEK_PHY_HWMON a visible Kconfig
# option. Since REALTEK_PHY is enabled for sunxi, pin the optional HWMON choice
# in the kernel config fragment so non-interactive syncconfig does not prompt.
if ! grep -q '^CONFIG_REALTEK_PHY=y$' "$KERNEL_CONFIG"; then
	echo "Expected CONFIG_REALTEK_PHY=y in $KERNEL_CONFIG" >&2
	exit 1
fi
sed -i '/^CONFIG_REALTEK_PHY_HWMON=/d; /^# CONFIG_REALTEK_PHY_HWMON is not set$/d' "$KERNEL_CONFIG"
printf '%s\n' '# CONFIG_REALTEK_PHY_HWMON is not set' >> "$KERNEL_CONFIG"
