#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
	echo "Usage: $0 OPENWRT_SOURCE_DIR" >&2
	exit 2
fi

HERE="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OW_DIR="$1"
KERNEL_CONFIG="$OW_DIR/target/linux/sunxi/config-6.6"

find "$HERE/overlay" -type f -print | while IFS= read -r source_file; do
	relative_path=${source_file#"$HERE/overlay/"}
	target_file="$OW_DIR/$relative_path"
	if [ -f "$target_file" ] && cmp -s "$source_file" "$target_file"; then
		continue
	fi
	mkdir -p "$(dirname "$target_file")"
	cp -p "$source_file" "$target_file"
	touch "$target_file"
done

# Drop this obsolete project patch from an existing local build tree. It forces
# a three-argument callback although the pinned OpenWrt 24.10 header expects
# the two-argument set_wiphy_params callback.
rm -f "$OW_DIR/package/kernel/uwe5622/patches/080-cfg80211-set-wiphy-params-backport-radio-idx.patch"

# Linux 6.6 receives a backport that makes REALTEK_PHY_HWMON a visible Kconfig
# option. Since REALTEK_PHY is enabled for sunxi, pin the optional HWMON choice
# in the kernel config fragment so non-interactive syncconfig does not prompt.
if ! grep -q '^CONFIG_REALTEK_PHY=y$' "$KERNEL_CONFIG"; then
	echo "Expected CONFIG_REALTEK_PHY=y in $KERNEL_CONFIG" >&2
	exit 1
fi
HWMON_DISABLED='# CONFIG_REALTEK_PHY_HWMON is not set'
if ! grep -Fqx "$HWMON_DISABLED" "$KERNEL_CONFIG" || grep -q '^CONFIG_REALTEK_PHY_HWMON=' "$KERNEL_CONFIG"; then
	sed -i '/^CONFIG_REALTEK_PHY_HWMON=/d; /^# CONFIG_REALTEK_PHY_HWMON is not set$/d' "$KERNEL_CONFIG"
	printf '%s\n' "$HWMON_DISABLED" >> "$KERNEL_CONFIG"
fi
