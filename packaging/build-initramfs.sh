#!/bin/sh
# Generate the initial ramdisk (initramfs) containing PS5 hardware drivers
# (amdgpu, NXP mwifiex, and ostree rootfs mount drivers) required to boot.
set -e

mkdir -p /var/roothome

KVER=$(ls -1t /usr/lib/modules | head -n1)
if [ -z "$KVER" ]; then
    echo "Error: No kernel modules found in /usr/lib/modules"
    exit 1
fi

dracut --force --no-hostonly --kver "$KVER" "/usr/lib/modules/$KVER/initramfs.img"
cp "/usr/lib/modules/$KVER/initramfs.img" "/boot/initramfs-$KVER.img" 2>/dev/null || true
