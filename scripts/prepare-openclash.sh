#!/bin/sh
# Prepare the pinned OpenClash LuCI package for an OpenWrt build.
#
# The factory image intentionally uses one explicit upstream release. A
# missing or corrupt package is a hard error: silently building an image
# without the requested LuCI application is worse than stopping early.

set -eu

if [ "$#" -ne 1 ]; then
	printf 'Usage: %s OPENWRT_SOURCE_DIR\n' "$0" >&2
	exit 2
fi

OW_DIR=$1
OPENCLASH_VERSION=0.48.002
OPENCLASH_ASSET="luci-app-openclash_${OPENCLASH_VERSION}_all.ipk"
OPENCLASH_URL="https://github.com/vernesong/OpenClash/releases/download/v${OPENCLASH_VERSION}/${OPENCLASH_ASSET}"
OPENCLASH_SHA256=f3f0d0514553aea8d542c62dc52ac26d1f79dbda24204280f1cb8ea7fff71e9e
PKG_DIR="$OW_DIR/package/luci-app-openclash-prebuilt"
DL_DIR="$OW_DIR/dl"
IPK="$DL_DIR/$OPENCLASH_ASSET"
TMP_IPK="${IPK}.tmp.$$"

detect_ipk_format() {
	if command -v ar >/dev/null 2>&1 && ar t "$IPK" >/dev/null 2>&1; then
		printf '%s\n' ar
		return 0
	fi
	if tar -tzf "$IPK" >/dev/null 2>&1; then
		printf '%s\n' tar
		return 0
	fi
	return 1
}

verify_ipk_sha256() {
	_actual_sha256=$(sha256sum "$1" 2>/dev/null | awk '{print $1}') || return 1
	[ "$_actual_sha256" = "$OPENCLASH_SHA256" ]
}

cleanup() {
	rm -f "$TMP_IPK"
}
trap cleanup EXIT HUP INT TERM

printf '>> Preparing OpenClash v%s\n' "$OPENCLASH_VERSION"
mkdir -p "$DL_DIR"

# Remove the old optional/latest name from trees created by earlier revisions.
rm -f "$DL_DIR/luci-app-openclash-latest.ipk"

IPK_FORMAT=
if [ -s "$IPK" ]; then
	IPK_FORMAT=$(detect_ipk_format || true)
	if [ -n "$IPK_FORMAT" ] && ! verify_ipk_sha256 "$IPK"; then
		printf '%s\n' 'Cached OpenClash package has the wrong SHA-256; downloading it again.'
		IPK_FORMAT=
	fi
fi
if [ -z "$IPK_FORMAT" ]; then
	command -v curl >/dev/null 2>&1 || {
		printf '%s\n' 'OpenClash requires curl on the build host' >&2
		exit 1
	}
	command -v sha256sum >/dev/null 2>&1 || {
		printf '%s\n' 'OpenClash requires sha256sum on the build host' >&2
		exit 1
	}
	command -v tar >/dev/null 2>&1 || {
		printf '%s\n' 'OpenClash requires tar on the build host' >&2
		exit 1
	}
	printf 'Downloading %s\n' "$OPENCLASH_URL"
	curl -fL --retry 3 --connect-timeout 15 --max-time 180 \
		-H 'User-Agent: FPS1024-OpenWRT-builder' \
		-o "$TMP_IPK" "$OPENCLASH_URL"
	verify_ipk_sha256 "$TMP_IPK" || {
		printf 'OpenClash SHA-256 mismatch; expected %s\n' "$OPENCLASH_SHA256" >&2
		exit 1
	}
	mv -f "$TMP_IPK" "$IPK"
	IPK_FORMAT=$(detect_ipk_format || true)
fi

command -v sha256sum >/dev/null 2>&1 || {
	printf '%s\n' 'OpenClash requires sha256sum on the build host' >&2
	exit 1
}
verify_ipk_sha256 "$IPK" || {
	printf 'OpenClash SHA-256 mismatch; expected %s\n' "$OPENCLASH_SHA256" >&2
	exit 1
}

[ -n "$IPK_FORMAT" ] || {
	printf 'Downloaded OpenClash archive is invalid: %s\n' "$IPK" >&2
	exit 1
}
case "$IPK_FORMAT" in
ar)
	ar t "$IPK" | grep -qx 'data.tar.gz'
	;;
tar)
	tar -tzf "$IPK" 2>/dev/null | grep -Eq '(^|/)data\.tar\.gz$'
	;;
esac || {
	printf 'OpenClash IPK has no data.tar.gz payload: %s\n' "$IPK" >&2
	exit 1
}

read_control_archive() {
	case "$IPK_FORMAT" in
		ar)
			ar p "$IPK" control.tar.gz
			;;
		tar)
			tar -xOzf "$IPK" ./control.tar.gz 2>/dev/null || \
				tar -xOzf "$IPK" control.tar.gz 2>/dev/null
			;;
	esac
}

CONTROL=$(read_control_archive 2>/dev/null | tar -xzO ./control 2>/dev/null || \
	read_control_archive 2>/dev/null | tar -xzO control 2>/dev/null) || {
	printf 'OpenClash IPK has no readable control metadata: %s\n' "$IPK" >&2
	exit 1
}
PACKAGE_NAME=$(printf '%s\n' "$CONTROL" | sed -n 's/^Package:[[:space:]]*//p' | sed -n '1p')
PACKAGE_VERSION=$(printf '%s\n' "$CONTROL" | sed -n 's/^Version:[[:space:]]*//p' | sed -n '1p')
PACKAGE_ARCH=$(printf '%s\n' "$CONTROL" | sed -n 's/^Architecture:[[:space:]]*//p' | sed -n '1p')
[ "$PACKAGE_NAME" = luci-app-openclash ] || {
	printf 'Unexpected OpenClash package name: %s\n' "${PACKAGE_NAME:-<empty>}" >&2
	exit 1
}
[ "$PACKAGE_VERSION" = "$OPENCLASH_VERSION" ] || {
	printf 'OpenClash package version is %s, expected %s\n' "${PACKAGE_VERSION:-<empty>}" "$OPENCLASH_VERSION" >&2
	exit 1
}
[ "$PACKAGE_ARCH" = all ] || {
	printf 'OpenClash package architecture is %s, expected all\n' "${PACKAGE_ARCH:-<empty>}" >&2
	exit 1
}

rm -rf "$PKG_DIR"
mkdir -p "$PKG_DIR"
cat > "$PKG_DIR/Makefile" <<EOF
include \$(TOPDIR)/rules.mk

PKG_NAME:=luci-app-openclash
PKG_VERSION:=$OPENCLASH_VERSION
PKG_RELEASE:=1
PKG_BUILD_DIR:=\$(BUILD_DIR)/\$(PKG_NAME)-prebuilt-\$(PKG_VERSION)
PKGARCH:=all

include \$(INCLUDE_DIR)/package.mk

define Package/luci-app-openclash
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=OpenClash LuCI application (v$OPENCLASH_VERSION)
  DEPENDS:=+dnsmasq-full +bash +curl +ca-bundle +ip-full +ruby +ruby-yaml +kmod-tun +kmod-inet-diag +unzip +kmod-nft-tproxy +kmod-nf-conntrack-netlink +luci +luci-compat +luci-base
endef

define Package/luci-app-openclash/description
  OpenClash LuCI application unpacked from the pinned upstream v$OPENCLASH_VERSION release.
endef

define Package/luci-app-openclash/conffiles
/etc/config/openclash
endef

define Build/Prepare
	\$(RM) -r \$(PKG_BUILD_DIR)
	\$(INSTALL_DIR) \$(PKG_BUILD_DIR)/root
	{ if ar t "\$(DL_DIR)/$OPENCLASH_ASSET" >/dev/null 2>&1; then \
		ar p "\$(DL_DIR)/$OPENCLASH_ASSET" data.tar.gz; \
	else \
		tar -xOzf "\$(DL_DIR)/$OPENCLASH_ASSET" ./data.tar.gz 2>/dev/null || \
		tar -xOzf "\$(DL_DIR)/$OPENCLASH_ASSET" data.tar.gz; \
	fi; } | tar -xzf - -C \$(PKG_BUILD_DIR)/root
endef

define Build/Compile
endef

define Package/luci-app-openclash/install
	\$(CP) \$(PKG_BUILD_DIR)/root/. \$(1)/
endef

\$(eval \$(call BuildPackage,luci-app-openclash))
EOF

printf 'OpenClash package prepared: %s\n' "$IPK"
