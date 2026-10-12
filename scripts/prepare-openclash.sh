#!/bin/sh
# Prepare the latest optional OpenClash LuCI package for an OpenWrt build.
#
# The package is deliberately optional: a GitHub release/API outage must not
# prevent the router image itself from being built.  All OpenClash runtime
# dependencies are selected separately in the main configuration and therefore
# remain mandatory.

set -eu

if [ "$#" -ne 1 ]; then
	printf 'Usage: %s OPENWRT_SOURCE_DIR\n' "$0" >&2
	exit 2
fi

OW_DIR=$1
HERE=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PKG_DIR="$OW_DIR/package/luci-app-openclash-prebuilt"
DL_DIR="$OW_DIR/dl"
IPK="$DL_DIR/luci-app-openclash-latest.ipk"
API_JSON="${TMPDIR:-/tmp}/openclash-release.$$.json"

printf '%s\n' '>> Preparing optional OpenClash package'
mkdir -p "$DL_DIR"
# Do not accidentally reuse an older generated package in an incremental tree
# when the latest-release request fails.
rm -rf "$PKG_DIR"
rm -f "$IPK"

# A checked-in package in apps/ is useful for offline/local builds.  In CI the
# latest release is preferred so the image does not silently ship an old app.
LOCAL_IPK=''
for candidate in "$HERE"/apps/luci-app-openclash*.ipk; do
	[ -f "$candidate" ] || continue
	LOCAL_IPK=$candidate
	break
done

ASSET_NAME=''
ASSET_URL=''
if command -v curl >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
	if curl -fsSL --retry 3 --connect-timeout 15 --max-time 60 \
		-H 'Accept: application/vnd.github+json' \
		-H 'User-Agent: FPS1024-OpenWRT-builder' \
		https://api.github.com/repos/vernesong/OpenClash/releases/latest > "$API_JSON" 2>/dev/null; then
		ASSET_LINES=$(python3 - "$API_JSON" <<'PY'
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    release = json.load(fh)

assets = []
for asset in release.get("assets", []):
    name = asset.get("name", "")
    url = asset.get("browser_download_url", "")
    if name.startswith("luci-app-openclash") and name.endswith(".ipk") and url:
        assets.append((name, url))

# Some releases publish an explicitly nftables-labelled asset.  Prefer it;
# otherwise the normal all-architecture OpenClash IPK is the nftables-capable
# LuCI application and uses the nftables dependencies selected by the build.
nft = [x for x in assets if re.search(r"nft|nfat", x[0], re.I)]
chosen = (nft or assets)
if chosen:
    print(chosen[0][0])
    print(chosen[0][1])
PY
)
		ASSET_NAME=$(printf '%s\n' "$ASSET_LINES" | sed -n '1p')
		ASSET_URL=$(printf '%s\n' "$ASSET_LINES" | sed -n '2p')
	fi
fi

if [ -n "$ASSET_URL" ]; then
	printf 'Latest release asset: %s\n' "$ASSET_NAME"
	if ! curl -fL --retry 3 --connect-timeout 15 --max-time 180 \
		-H 'User-Agent: FPS1024-OpenWRT-builder' "$ASSET_URL" -o "$IPK"; then
		printf '%s\n' 'WARNING: OpenClash download failed; skipping optional app.'
		[ -n "$LOCAL_IPK" ] || exit 0
		printf 'Using local fallback: %s\n' "$LOCAL_IPK"
		cp -f "$LOCAL_IPK" "$IPK"
	fi
elif [ -n "$LOCAL_IPK" ]; then
	printf 'Release API unavailable; using local package: %s\n' "$LOCAL_IPK"
	cp -f "$LOCAL_IPK" "$IPK"
else
	printf '%s\n' 'WARNING: no OpenClash release or local package found; skipping optional app.'
	exit 0
fi

# Verify the archive before creating a package definition.  A partial download
# must never enter the firmware rootfs.
if ! tar -tzf "$IPK" >/dev/null 2>&1; then
	printf '%s\n' 'WARNING: downloaded OpenClash file is not a valid IPK; skipping app.'
	exit 0
fi

VERSION=$(tar -xOzf "$IPK" ./control.tar.gz 2>/dev/null \
	| tar -xzO ./control 2>/dev/null \
	| sed -n 's/^Version:[[:space:]]*//p' | sed -n '1p' || true)
VERSION=${VERSION:-latest}
# Keep the generated Makefile safe even if an upstream version string changes.
VERSION=$(printf '%s' "$VERSION" | tr -cd 'A-Za-z0-9._+-')
[ -n "$VERSION" ] || VERSION=latest

mkdir -p "$PKG_DIR"
cat > "$PKG_DIR/Makefile" <<'EOF'
include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-openclash
PKG_VERSION:=__OPENCLASH_VERSION__
PKG_RELEASE:=1
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-prebuilt-$(PKG_VERSION)
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-openclash
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=OpenClash LuCI application (prebuilt release)
  DEPENDS:=+dnsmasq-full +bash +curl +ca-bundle +ip-full +ruby +ruby-yaml +kmod-tun +kmod-inet-diag +unzip +kmod-nft-tproxy +kmod-nf-conntrack-netlink +luci-compat +luci-base
endef

define Package/luci-app-openclash/description
  OpenClash LuCI application unpacked from the latest upstream release.
  The package is optional; its runtime dependencies are selected by the
  project configuration and are not optional.
endef

define Package/luci-app-openclash/conffiles
/etc/config/openclash
endef

define Build/Prepare
	$(RM) -r $(PKG_BUILD_DIR)
	$(INSTALL_DIR) $(PKG_BUILD_DIR)/root
	tar -xOzf $(DL_DIR)/luci-app-openclash-latest.ipk ./data.tar.gz | tar -xzf - -C $(PKG_BUILD_DIR)/root
endef

define Build/Compile
endef

define Package/luci-app-openclash/install
	$(CP) $(PKG_BUILD_DIR)/root/. $(1)/
endef

$(eval $(call BuildPackage,luci-app-openclash))
EOF
sed -i "s/__OPENCLASH_VERSION__/$VERSION/" "$PKG_DIR/Makefile"
printf 'OpenClash package prepared: version %s\n' "$VERSION"
