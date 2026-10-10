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
	rm -rf "$OW_DIR"
	git clone --no-checkout https://github.com/openwrt/openwrt.git "$OW_DIR"
fi

git -C "$OW_DIR" fetch --depth 1 origin "$OW_COMMIT"
git -C "$OW_DIR" checkout --detach "$OW_COMMIT"
echo "OpenWrt: $(git -C "$OW_DIR" rev-parse HEAD)"

echo ">> Applying project overlay"
cp -a "$HERE/overlay/." "$OW_DIR/"

cd "$OW_DIR"
cat > .config <<EOF
CONFIG_TARGET_sunxi=y
CONFIG_TARGET_sunxi_cortexa53=y
CONFIG_TARGET_sunxi_cortexa53_DEVICE_${DEVICE}=y
EOF

echo ">> Configure"
run_logged "$LOG_DIR/defconfig.log" make defconfig
cp .config "$LOG_DIR/openwrt.config"

echo ">> Download sources"
run_logged "$LOG_DIR/download.log" make -j"$JOBS" download

echo ">> Build and install OpenWrt toolchain"
run_logged "$LOG_DIR/toolchain.log" make -j"$JOBS" toolchain/install

echo ">> Compile UWE5622 kernel package first"
run_logged "$LOG_DIR/uwe5622.log" make -j"$JOBS" package/kernel/uwe5622/compile V=s

echo ">> Build image"
run_logged "$LOG_DIR/build.log" make -j"$JOBS"

echo ">> Verify expected image and driver packages exist"
IMAGE_DIR="bin/targets/sunxi/cortexa53"
test -d "$IMAGE_DIR"
find "$IMAGE_DIR" -maxdepth 1 -type f -name '*xunlong_orangepi-3-lts*' -print > "$LOG_DIR/images.txt"
cat "$LOG_DIR/images.txt"
grep -q '\.img\.gz$' "$LOG_DIR/images.txt"
find bin/targets/sunxi/cortexa53/packages -type f \( -name 'kmod-uwe5622*.ipk' -o -name 'uwe5622-firmware*.ipk' \) -print > "$LOG_DIR/uwe5622-packages.txt"
cat "$LOG_DIR/uwe5622-packages.txt"
grep -q 'kmod-uwe5622' "$LOG_DIR/uwe5622-packages.txt"
grep -q 'uwe5622-firmware' "$LOG_DIR/uwe5622-packages.txt"

echo "Build completed: $OW_DIR/$IMAGE_DIR"
