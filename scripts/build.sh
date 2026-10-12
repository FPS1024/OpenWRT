#!/bin/sh
# Reproducible OpenWrt build for Orange Pi 3 LTS.
set -eu

OW_COMMIT="${OW_COMMIT:-58584c6f2829a7e5d77376ab68aae3dcc4a392d8}"
JOBS="${JOBS:-$(nproc)}"
INCLUDE_DEV_TOOLS="${INCLUDE_DEV_TOOLS:-0}"
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

# Some local sandboxes reject the Unix socket used by the fakeroot binary
# built by OpenWrt.  A system fakeroot can still create the package archives;
# use it only when the OpenWrt host helper fails its harmless probe.
prepare_fakeroot() {
	_fakeroot_bin="$OW_DIR/staging_dir/host/bin/fakeroot"
	if [ ! -x "$_fakeroot_bin" ] || "$_fakeroot_bin" true >/dev/null 2>&1; then
		return 0
	fi
	if [ -x /usr/bin/fakeroot ]; then
		if [ ! -e "$_fakeroot_bin.openwrt" ]; then
			cp -p "$_fakeroot_bin" "$_fakeroot_bin.openwrt"
		fi
		cat > "$_fakeroot_bin" <<'EOF'
#!/bin/sh
exec /usr/bin/fakeroot "$@"
EOF
		chmod 0755 "$_fakeroot_bin"
		echo "Using /usr/bin/fakeroot because the OpenWrt host fakeroot cannot create its daemon socket"
		return 0
	fi
	echo "OpenWrt fakeroot cannot create its daemon socket and /usr/bin/fakeroot is unavailable" >&2
	return 1
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
if ! sh "$HERE/scripts/prepare-argon.sh" "$OW_DIR" > "$LOG_DIR/argon-sources.txt" 2>&1; then
	cat "$LOG_DIR/argon-sources.txt"
	exit 1
fi
cat "$LOG_DIR/argon-sources.txt"
# The image carries OpenClash runtime dependencies, but not the LuCI app.
# Remove generated leftovers from an older incremental build so it cannot be
# selected or copied into the image accidentally.
rm -rf "$OW_DIR/package/luci-app-openclash-prebuilt"
rm -f "$OW_DIR/dl/luci-app-openclash-latest.ipk"
if [ -d "$OW_DIR/bin/packages" ]; then
	find "$OW_DIR/bin/packages" -type f -name 'luci-app-openclash*.ipk' -delete
fi

if [ ! -s .config ] \
	|| ! grep -qx 'CONFIG_TARGET_sunxi=y' .config \
	|| ! grep -qx 'CONFIG_TARGET_sunxi_cortexa53=y' .config \
	|| ! grep -qx "CONFIG_TARGET_sunxi_cortexa53_DEVICE_${DEVICE}=y" .config; then
	cat > .config <<EOF
CONFIG_TARGET_sunxi=y
CONFIG_TARGET_sunxi_cortexa53=y
CONFIG_TARGET_sunxi_cortexa53_DEVICE_${DEVICE}=y
CONFIG_TARGET_ROOTFS_PARTSIZE=104
CONFIG_DEVEL=y
CONFIG_PER_FEED_REPO=y
CONFIG_FEED_packages=y
CONFIG_FEED_luci=y
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_uhttpd=y
CONFIG_PACKAGE_uhttpd-mod-ubus=y
CONFIG_PACKAGE_luci-compat=y
CONFIG_PACKAGE_kmod-tun=y
CONFIG_PACKAGE_kmod-inet-diag=y
CONFIG_PACKAGE_kmod-nft-tproxy=y
CONFIG_PACKAGE_kmod-nf-conntrack-netlink=y
# dnsmasq and dnsmasq-full install the same files; keep only full.
# CONFIG_PACKAGE_dnsmasq is not set
CONFIG_PACKAGE_dnsmasq-full=y
CONFIG_PACKAGE_libnettle=y
CONFIG_PACKAGE_libnetfilter-conntrack=y
CONFIG_PACKAGE_bash=y
CONFIG_PACKAGE_curl=y
CONFIG_PACKAGE_ca-bundle=y
CONFIG_PACKAGE_ip-full=y
CONFIG_PACKAGE_ruby=y
CONFIG_PACKAGE_ruby-yaml=y
CONFIG_PACKAGE_unzip=y
CONFIG_PACKAGE_luci-theme-argon=y
CONFIG_PACKAGE_luci-app-argon-config=y
CONFIG_LUCI_LANG_zh_Hans=y
CONFIG_PACKAGE_luci-i18n-argon-config-zh-cn=y
CONFIG_PACKAGE_luci-i18n-base-zh-cn=y
CONFIG_PACKAGE_luci-i18n-firewall-zh-cn=y
CONFIG_PACKAGE_luci-i18n-package-manager-zh-cn=y
CONFIG_PACKAGE_sfdisk=y
CONFIG_PACKAGE_partx-utils=y
CONFIG_PACKAGE_losetup=y
CONFIG_PACKAGE_resize2fs=y
EOF
if [ "$INCLUDE_DEV_TOOLS" = 1 ]; then
	cat >> .config <<'EOF'
# Optional target-side development tools. They are omitted from the default
# production image because they add a large amount of build time and size.
CONFIG_PACKAGE_git=y
CONFIG_PACKAGE_git-http=y
CONFIG_PACKAGE_make=y
CONFIG_PACKAGE_gcc=y
CONFIG_PACKAGE_binutils=y
EOF
else
	cat >> .config <<'EOF'
# CONFIG_PACKAGE_git is not set
# CONFIG_PACKAGE_git-http is not set
# CONFIG_PACKAGE_make is not set
# CONFIG_PACKAGE_gcc is not set
# CONFIG_PACKAGE_binutils is not set
EOF
fi
fi

# Drop a stale OpenClash selection from an existing local .config. Its runtime
# dependencies remain selected in the package list above.
sed -i '/^CONFIG_PACKAGE_luci-app-openclash=/d; /^# CONFIG_PACKAGE_luci-app-openclash is not set$/d' .config
printf '%s\n' '# CONFIG_PACKAGE_luci-app-openclash is not set' >> .config

# Keep the web UI selected in an existing incremental build tree too.
for symbol in \
	PER_FEED_REPO \
	DEVEL \
	FEED_packages \
	FEED_luci \
	PACKAGE_luci \
	PACKAGE_uhttpd \
	PACKAGE_uhttpd-mod-ubus \
	PACKAGE_luci-compat \
	PACKAGE_kmod-tun \
	PACKAGE_kmod-inet-diag \
	PACKAGE_kmod-nft-tproxy \
	PACKAGE_kmod-nf-conntrack-netlink \
	PACKAGE_dnsmasq-full \
	PACKAGE_libnettle \
	PACKAGE_libnetfilter-conntrack \
	PACKAGE_bash \
	PACKAGE_curl \
	PACKAGE_ca-bundle \
	PACKAGE_ip-full \
	PACKAGE_ruby \
	PACKAGE_ruby-yaml \
	PACKAGE_unzip \
	PACKAGE_luci-theme-argon \
	PACKAGE_luci-app-argon-config \
	LUCI_LANG_zh_Hans \
	PACKAGE_luci-i18n-argon-config-zh-cn \
	PACKAGE_luci-i18n-base-zh-cn \
	PACKAGE_luci-i18n-firewall-zh-cn \
	PACKAGE_luci-i18n-package-manager-zh-cn \
	PACKAGE_sfdisk \
	PACKAGE_partx-utils \
	PACKAGE_losetup \
	PACKAGE_resize2fs; do
	sed -i "/^CONFIG_${symbol}=/d; /^# CONFIG_${symbol} is not set$/d" .config
	printf 'CONFIG_%s=y\n' "$symbol" >> .config
done
if [ "$INCLUDE_DEV_TOOLS" = 1 ]; then
	for symbol in PACKAGE_git PACKAGE_git-http PACKAGE_make PACKAGE_gcc PACKAGE_binutils; do
		sed -i "/^CONFIG_${symbol}=/d; /^# CONFIG_${symbol} is not set$/d" .config
		printf 'CONFIG_%s=y\n' "$symbol" >> .config
	done
else
	# Clear transitive binutils selections left by an earlier dev-tool build.
	# defconfig can leave these orphaned package symbols enabled.
	for symbol in PACKAGE_git PACKAGE_git-http PACKAGE_make PACKAGE_gcc PACKAGE_binutils PACKAGE_ar PACKAGE_objdump PACKAGE_libbfd PACKAGE_libctf PACKAGE_libopcodes; do
		sed -i "/^CONFIG_${symbol}=/d; /^# CONFIG_${symbol} is not set$/d" .config
		printf '# CONFIG_%s is not set\n' "$symbol" >> .config
	done
fi

# An existing incremental .config may still contain the default dnsmasq
# variant.  Remove it before defconfig so package/install cannot collide with
# dnsmasq-full.
sed -i '/^CONFIG_PACKAGE_dnsmasq=y$/d; /^# CONFIG_PACKAGE_dnsmasq is not set$/d' .config
printf '%s\n' '# CONFIG_PACKAGE_dnsmasq is not set' >> .config
# Do not let an older incremental tree force the optional ccache host tool.
sed -i '/^CONFIG_CCACHE=y$/d; /^# CONFIG_CCACHE is not set$/d' .config
printf '%s\n' '# CONFIG_CCACHE is not set' >> .config
# Keep the image root partition fixed and small. First boot grows the existing
# root partition and its filesystem on the actual target device.
sed -i '/^CONFIG_TARGET_ROOTFS_PARTSIZE=/d' .config
printf '%s\n' 'CONFIG_TARGET_ROOTFS_PARTSIZE=104' >> .config

echo ">> Configure"
run_logged "$LOG_DIR/defconfig.log" make defconfig
cp .config "$LOG_DIR/openwrt.config"
grep -qx 'CONFIG_TARGET_ROOTFS_PARTSIZE=104' .config || {
	echo 'Unexpected rootfs partition size: keep the factory image small (104 MiB)' >&2
	exit 1
}
grep -qx 'CONFIG_FEED_packages=y' .config || { echo 'OpenWrt packages feed is not enabled' >&2; exit 1; }
grep -qx 'CONFIG_FEED_luci=y' .config || { echo 'LuCI package feed is not enabled' >&2; exit 1; }
grep -qx 'CONFIG_LUCI_LANG_zh_Hans=y' .config || { echo 'LuCI Simplified Chinese translations are not enabled' >&2; exit 1; }
grep -qx 'CONFIG_PACKAGE_luci-i18n-argon-config-zh-cn=y' .config || { echo 'Argon Config Chinese translation was not selected by defconfig' >&2; exit 1; }
if grep -qx 'CONFIG_PACKAGE_luci-app-openclash=y' .config; then
	echo 'OpenClash app must not be selected for the factory image' >&2
	exit 1
fi

echo ">> Download sources"
run_logged "$LOG_DIR/download.log" make -j"$JOBS" download

prepare_fakeroot

echo ">> Build packages (parallel; outputs are reused on later invocations)"
run_logged "$LOG_DIR/package-compile.log" make -j"$JOBS" package/compile

echo ">> Install packages into the image root"
run_logged "$LOG_DIR/package-install.log" make -j"$JOBS" package/install

echo ">> Build target image (serial and verbose; this is the short final stage)"
run_logged "$LOG_DIR/target-install.log" make -j1 V=s target/install

# The first-boot storage grower is part of the base-files overlay. Verify that
# package/install copied it into the actual image root and enabled it at S99;
# otherwise a factory image would keep only the fixed 104 MiB root partition.
STORAGE_INIT=$(find "$OW_DIR/build_dir" -type f -path '*/root-sunxi/etc/init.d/opi3lts-expand-storage' -print -quit)
test -n "$STORAGE_INIT" || { echo 'SD-card expansion init script is missing from the image root' >&2; exit 1; }
STORAGE_ROOT=${STORAGE_INIT%/etc/init.d/opi3lts-expand-storage}
test -f "$STORAGE_ROOT/lib/preinit/79_opi3lts_expand_storage" || {
	echo 'SD-card expansion preinit hook is missing from the image root' >&2
	exit 1
}
test -L "$STORAGE_ROOT/etc/rc.d/S99opi3lts-expand-storage" || {
	echo 'SD-card expansion init script is not enabled at S99' >&2
	exit 1
}

echo ">> Generate package indexes and checksums"
run_logged "$LOG_DIR/package-index.log" make -j"$JOBS" package/index json_overview_image_info checksum

echo ">> Verify expected image and driver packages exist"
IMAGE_DIR="bin/targets/sunxi/cortexa53"
test -d "$IMAGE_DIR"
MANIFEST="$IMAGE_DIR/openwrt-sunxi-cortexa53-${DEVICE}.manifest"
test -s "$MANIFEST" || { echo "Image manifest is missing: $MANIFEST" >&2; exit 1; }
for package in \
	luci-base luci-mod-admin-full luci-compat uhttpd uhttpd-mod-ubus \
	dnsmasq-full libnettle8 libnetfilter-conntrack3 \
	bash curl ca-bundle ip-full ruby ruby-yaml unzip \
	sfdisk partx-utils losetup resize2fs \
	luci-theme-argon luci-app-argon-config \
	luci-i18n-argon-config-zh-cn luci-i18n-base-zh-cn \
	luci-i18n-firewall-zh-cn luci-i18n-package-manager-zh-cn; do
	grep -q "^${package} " "$MANIFEST" || { echo "Expected web-admin package is missing: $package" >&2; exit 1; }
done
if [ "$INCLUDE_DEV_TOOLS" = 1 ]; then
	for package in git git-http make gcc binutils; do
		grep -q "^${package} " "$MANIFEST" || { echo "Requested development package is missing: $package" >&2; exit 1; }
	done
fi
if grep -q '^luci-app-openclash ' "$MANIFEST"; then
	echo 'Unexpected OpenClash app package found in image manifest' >&2
	exit 1
fi
echo 'OpenClash app is not bundled; its runtime dependencies are included'
find "$IMAGE_DIR" -maxdepth 1 -type f -name '*xunlong_orangepi-3-lts*' -print > "$LOG_DIR/images.txt"
cat "$LOG_DIR/images.txt"
grep -q '\.img\.gz$' "$LOG_DIR/images.txt" || { echo 'Orange Pi 3 LTS .img.gz image was not generated' >&2; exit 1; }
SQUASHFS_IMAGE="$IMAGE_DIR/openwrt-sunxi-cortexa53-${DEVICE}-squashfs-sdcard.img.gz"
test -s "$SQUASHFS_IMAGE" || { echo "SquashFS image is missing: $SQUASHFS_IMAGE" >&2; exit 1; }
SQUASHFS_BYTES=$(wc -c < "$SQUASHFS_IMAGE")
[ "$SQUASHFS_BYTES" -lt 268435456 ] || {
	echo "SquashFS image is unexpectedly large (${SQUASHFS_BYTES} bytes); refusing an artificial multi-gigabyte image" >&2
	exit 1
}
sh "$HERE/scripts/verify-image.sh" "$OW_DIR" "$OW_DIR/$SQUASHFS_IMAGE"
for package in kmod-tun kmod-inet-diag kmod-nft-tproxy kmod-nf-conntrack-netlink; do
	grep -q "^${package} " "$MANIFEST" || { echo "Kernel-matched ${package} package is missing from the image" >&2; exit 1; }
done
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
