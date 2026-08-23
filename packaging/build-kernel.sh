#!/bin/bash
set -e
shopt -s nullglob

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PATCHES_DIR="$SCRIPT_DIR/external/ps5-linux-patches"
MWIFIEX_PATCHES_DIR="$SCRIPT_DIR/external/ps5-linux-mwifiex"
BUILD_DIR="$SCRIPT_DIR/build"
STAGING_DIR="$BUILD_DIR/staging"
OUT_DIR="$SCRIPT_DIR/dist-rpms"
RPMBUILD_DIR="$BUILD_DIR/rpmbuild"

mkdir -p "$BUILD_DIR" "$STAGING_DIR" "$OUT_DIR" "$RPMBUILD_DIR"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

LINUX_VER="$(sed -nE 's/^# Linux\/[^ ]+ ([0-9]+\.[0-9]+(\.[0-9]+)?) .*/\1/p' "$PATCHES_DIR/.config" | head -1)"
LINUX_SRC="$BUILD_DIR/linux-$LINUX_VER"

if [ ! -d "$LINUX_SRC" ]; then
    git clone --branch "v$LINUX_VER" --depth 1 https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git "$LINUX_SRC"
    for p in "$PATCHES_DIR"/*.patch; do
        git -C "$LINUX_SRC" apply --exclude=Makefile "$p"
    done
    cp "$PATCHES_DIR/.config" "$LINUX_SRC/.config"
fi

cd "$LINUX_SRC"
make olddefconfig
make -j"$(nproc)" bzImage modules

KVER="$(make -s kernelrelease)"
CLEAN_VER="$(echo "$KVER" | sed -E 's/-.*//')"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR/boot" "$STAGING_DIR/usr/lib/modules"

cp arch/x86/boot/bzImage "$STAGING_DIR/boot/vmlinuz-$KVER"
cp System.map             "$STAGING_DIR/boot/System.map-$KVER"
cp .config                "$STAGING_DIR/boot/config-$KVER"

make modules_install INSTALL_MOD_PATH="$STAGING_DIR/usr" INSTALL_MOD_STRIP=1
rm -f "$STAGING_DIR/usr/lib/modules/$KVER/build" "$STAGING_DIR/usr/lib/modules/$KVER/source"

MWIFIEX_SRC="$BUILD_DIR/mwifiex-src"
if [ ! -d "$MWIFIEX_SRC" ]; then
    git clone --depth 1 --branch lf-6.18.2_1.0.0 https://github.com/nxp-imx/mwifiex.git "$MWIFIEX_SRC"
    git -C "$MWIFIEX_SRC" apply "$MWIFIEX_PATCHES_DIR/ps5-iw620.patch"
    git -C "$MWIFIEX_SRC" apply "$MWIFIEX_PATCHES_DIR/ps5-iw620-cmd-timeout-recover.patch"
    git -C "$MWIFIEX_SRC" apply "$MWIFIEX_PATCHES_DIR/ps5-iw620-kernel71-compat.patch"
fi

make -C "$MWIFIEX_SRC" CONFIG_OBJTOOL= KERNELDIR="$LINUX_SRC" ARCH=x86 -j"$(nproc)"

EXTRA_DIR="$STAGING_DIR/usr/lib/modules/$KVER/extra/ps5-iw620"
mkdir -p "$EXTRA_DIR"
install -m 0644 "$MWIFIEX_SRC/mlan.ko" "$EXTRA_DIR/mlan.ko"
install -m 0644 "$MWIFIEX_SRC/moal.ko" "$EXTRA_DIR/moal.ko"

depmod -b "$STAGING_DIR/usr" "$KVER"

rpmbuild -bb \
    --define "_topdir $RPMBUILD_DIR" \
    --define "stagedir $STAGING_DIR" \
    --define "kver $KVER" \
    --define "ver $CLEAN_VER" \
    "$SCRIPT_DIR/packaging/kernel-ps5.spec"

cp -r "$RPMBUILD_DIR"/RPMS/*/*.rpm "$OUT_DIR/"
