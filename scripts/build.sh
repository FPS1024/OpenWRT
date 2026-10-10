#!/bin/sh
# Reproducible OpenWrt build for Orange Pi 3 LTS.
set -eu

OW_COMMIT="${OW_COMMIT:-58584c6f2829a7e5d77376ab68aae3dcc4a392d8}"
JOBS="${JOBS:-$(nproc)}"
DEVICE="xunlong_orangepi-3-lts"
HERE="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OW_DIR="${OPENWRT_DIR:-$HERE/.work/openwrt}"
LOG_DIR="${LOG_DIR:-$HERE/_logs}"

mkdir -p "$(dirname "$OW_DIR")" "$LOG_DIR"
export FORCE_UNSAFE_CONFIGURE=1

run_logged() {
	log_file="$1"
	shift
	if "$@" > "$log_file" 2>&1; then
		cat "$log_file"
	else
		cat "$log_file"
		return 1
	fi
}

if [ ! -d "$OW_DIR/.git" ]; then
	echo ">> Cloning OpenWrt at $OW_COMMIT"
	if [ -e "$OW_DIR" ] && [ -n "$(find "$OW_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
		echo "Refusing to replace non-empty directory without a Git checkout: $OW_DIR" >&2
		exit 1
	fi
	git clone --no-checkout https://github.com/openwrt/openwrt.git "$OW_DIR"
fi

if ! git -C "$OW_DIR" cat-file -e "$OW_COMMIT^{commit}" 2>/dev/null; then
	git -C "$OW_DIR" fetch --depth 1 origin "$OW_COMMIT"
fi
git -C "$OW_DIR" checkout --detach "$OW_COMMIT"
echo "OpenWrt: $(git -C "$OW_DIR" rev-parse HEAD)"

echo ">> Applying project overlay"
sh "$HERE/scripts/apply-overlay.sh" "$OW_DIR"

cd "$OW_DIR"
if [ ! -s .config ] \
	|| ! grep -qx 'CONFIG_TARGET_sunxi=y' .config \
	|| ! grep -qx 'CONFIG_TARGET_sunxi_cortexa53=y' .config \
	|| ! grep -qx "CONFIG_TARGET_sunxi_cortexa53_DEVICE_${DEVICE}=y" .config; then
	cat > .config <<EOF
CONFIG_TARGET_sunxi=y
CONFIG_TARGET_sunxi_cortexa53=y
CONFIG_TARGET_sunxi_cortexa53_DEVICE_${DEVICE}=y
EOF
fi

echo ">> Configure"
run_logged "$LOG_DIR/defconfig.log" make defconfig
cp .config "$LOG_DIR/openwrt.config"

echo ">> Download sources"
run_logged "$LOG_DIR/download.log" make -j"$JOBS" download

echo ">> Build image (OpenWrt make reuses completed toolchain, kernel, and package outputs)"
if ! make -j"$JOBS" > "$LOG_DIR/build.log" 2>&1; then
	cat "$LOG_DIR/build.log"
	if grep -q 'ERROR: target/linux failed to build' "$LOG_DIR/build.log"; then
		df -h > "$LOG_DIR/disk-after-build-failure.txt"
		df -i >> "$LOG_DIR/disk-after-build-failure.txt"
		echo ">> Retry target/linux/install serially with verbose output"
		if ! make -j1 V=s target/linux/install > "$LOG_DIR/target-linux-install.log" 2>&1; then
			cat "$LOG_DIR/target-linux-install.log"
			exit 1
		fi
		echo ">> Verbose target install passed; resume full image build"
		run_logged "$LOG_DIR/build-retry.log" make -j"$JOBS"
	else
		exit 1
	fi
fi

echo ">> Verify expected image and driver packages exist"
IMAGE_DIR="bin/targets/sunxi/cortexa53"
test -d "$IMAGE_DIR"
find "$IMAGE_DIR" -maxdepth 1 -type f -name '*xunlong_orangepi-3-lts*' -print > "$LOG_DIR/images.txt"
cat "$LOG_DIR/images.txt"
grep -q '\.img\.gz$' "$LOG_DIR/images.txt" || { echo 'Orange Pi 3 LTS .img.gz image was not generated' >&2; exit 1; }
: > "$LOG_DIR/uwe5622-packages.txt"
for package_dir in "$IMAGE_DIR/packages" bin/packages; do
	if [ -d "$package_dir" ]; then
		find "$package_dir" -type f \( -name 'kmod-uwe5622*.ipk' -o -name 'uwe5622-firmware*.ipk' \) -print >> "$LOG_DIR/uwe5622-packages.txt"
	fi
done
cat "$LOG_DIR/uwe5622-packages.txt"
grep -q 'kmod-uwe5622' "$LOG_DIR/uwe5622-packages.txt" || { echo 'kmod-uwe5622 package was not generated' >&2; exit 1; }
grep -q 'uwe5622-firmware' "$LOG_DIR/uwe5622-packages.txt" || { echo 'uwe5622-firmware package was not generated' >&2; exit 1; }

echo "Build completed: $OW_DIR/$IMAGE_DIR"
