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
	_run_log_file="$1"
	shift
	_run_status_file="${_run_log_file}.status"
	rm -f "$_run_status_file"
	(
		set +e
		"$@"
		_run_exit_status=$?
		printf '%s\n' "$_run_exit_status" > "$_run_status_file"
		exit "$_run_exit_status"
	) 2>&1 | tee "$_run_log_file"
	if [ ! -f "$_run_status_file" ]; then
		return 1
	fi
	_run_logged_status=$(cat "$_run_status_file")
	rm -f "$_run_status_file"
	return "$_run_logged_status"
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

echo ">> Update and install LuCI package feeds"
run_logged "$LOG_DIR/feeds-update.log" ./scripts/feeds update packages luci
run_logged "$LOG_DIR/feeds-install-packages.log" ./scripts/feeds install -a -p packages
run_logged "$LOG_DIR/feeds-install-luci.log" ./scripts/feeds install -a -p luci

if [ ! -s .config ] \
	|| ! grep -qx 'CONFIG_TARGET_sunxi=y' .config \
	|| ! grep -qx 'CONFIG_TARGET_sunxi_cortexa53=y' .config \
	|| ! grep -qx "CONFIG_TARGET_sunxi_cortexa53_DEVICE_${DEVICE}=y" .config; then
	cat > .config <<EOF
CONFIG_TARGET_sunxi=y
CONFIG_TARGET_sunxi_cortexa53=y
CONFIG_TARGET_sunxi_cortexa53_DEVICE_${DEVICE}=y
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_uhttpd=y
CONFIG_PACKAGE_uhttpd-mod-ubus=y
EOF
fi

# Keep the web UI selected in an existing incremental build tree too.
for symbol in luci uhttpd uhttpd-mod-ubus; do
	sed -i "/^CONFIG_PACKAGE_${symbol}=/d; /^# CONFIG_PACKAGE_${symbol} is not set$/d" .config
	printf 'CONFIG_PACKAGE_%s=y\n' "$symbol" >> .config
done

echo ">> Configure"
run_logged "$LOG_DIR/defconfig.log" make defconfig
cp .config "$LOG_DIR/openwrt.config"

echo ">> Download sources"
run_logged "$LOG_DIR/download.log" make -j"$JOBS" download

echo ">> Build firmware (make reuses valid outputs and rebuilds any missing dependencies)"
if ! run_logged "$LOG_DIR/build.log" make -j"$JOBS"; then
	if grep -q 'ERROR: target/linux failed to build' "$LOG_DIR/build.log"; then
		df -h > "$LOG_DIR/disk-after-build-failure.txt"
		df -i >> "$LOG_DIR/disk-after-build-failure.txt"
		echo ">> Retry target/linux/install serially with verbose output"
		if ! run_logged "$LOG_DIR/target-linux-install.log" make -j1 V=s target/linux/install; then
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
MANIFEST="$IMAGE_DIR/openwrt-sunxi-cortexa53-${DEVICE}.manifest"
test -s "$MANIFEST" || { echo "Image manifest is missing: $MANIFEST" >&2; exit 1; }
for package in luci-base luci-mod-admin-full uhttpd uhttpd-mod-ubus; do
	grep -q "^${package} " "$MANIFEST" || { echo "Expected web-admin package is missing: $package" >&2; exit 1; }
done
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
