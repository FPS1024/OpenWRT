#!/bin/sh
# Add upstream Argon packages to the OpenWrt build tree.
set -eu

if [ "$#" -ne 1 ]; then
	echo "Usage: $0 OPENWRT_SOURCE_DIR" >&2
	exit 2
fi

OW_DIR=$1
ARGON_THEME_REF=${ARGON_THEME_REF:-master}
ARGON_CONFIG_REF=${ARGON_CONFIG_REF:-master}

clone_package() {
	name=$1
	repository=$2
	ref=$3
	directory="$OW_DIR/package/$name"

	if [ -d "$directory/.git" ]; then
		:
	elif [ -e "$directory" ]; then
		echo "Refusing to replace non-Git package directory: $directory" >&2
		exit 1
	else
		git clone --depth 1 --branch "$ref" "$repository" "$directory"
	fi

	if [ ! -s "$directory/Makefile" ]; then
		echo "Package Makefile is missing: $directory/Makefile" >&2
		exit 1
	fi
	printf '%s %s %s\n' "$name" "$ref" "$(git -C "$directory" rev-parse HEAD)"
}

echo ">> Add Argon theme and settings package"
clone_package luci-theme-argon https://github.com/jerrykuku/luci-theme-argon.git "$ARGON_THEME_REF"
clone_package luci-app-argon-config https://github.com/jerrykuku/luci-app-argon-config.git "$ARGON_CONFIG_REF"
