#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
	echo "Usage: $0 OPENWRT_SOURCE_DIR" >&2
	exit 2
fi

HERE="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OW_DIR="$1"
CORTEXA53_KERNEL_CONFIG="$OW_DIR/target/linux/sunxi/cortexa53/config-6.12"

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

# Remove the old project DTS patch after switching from the Linux 6.6 tree.
rm -f "$OW_DIR/target/linux/sunxi/patches-6.6/460-arm64-dts-allwinner-add-orangepi-3-lts.patch"
rmdir "$OW_DIR/target/linux/sunxi/patches-6.6" 2>/dev/null || true

# Drop this obsolete project patch from existing build trees. It forced the
# three-argument callback unconditionally; the current patch selects that
# signature only when the cfg80211 backport API is enabled.
rm -f "$OW_DIR/package/kernel/uwe5622/patches/080-cfg80211-set-wiphy-params-backport-radio-idx.patch"

# The overlay copies files but never deletes them, so patches that the feeds
# still ship have to be removed explicitly.  Node 24 replaced this macOS-only
# patch: its context targets the old gyp make.py template, and this project
# only ever builds on Linux.
rm -f "$OW_DIR/feeds/packages/lang/node/patches/007-fix_host_build_on_macos.patch"

# The H6 RTC driver also registers the OSC32K_FANOUT clock provider used by
# the Orange Pi 3 LTS Wi-Fi MMC power sequence. Without RTC_CLASS the provider
# is omitted, leaving wifi-pwrseq deferred and preventing mmc1 from probing.
for symbol in RTC_CLASS RTC_DRV_SUN6I; do
	if ! grep -Fqx "CONFIG_${symbol}=y" "$CORTEXA53_KERNEL_CONFIG"; then
		sed -i "/^CONFIG_${symbol}=/d; /^# CONFIG_${symbol} is not set$/d" "$CORTEXA53_KERNEL_CONFIG"
		printf 'CONFIG_%s=y\n' "$symbol" >> "$CORTEXA53_KERNEL_CONFIG"
	fi
done
