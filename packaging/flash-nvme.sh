#!/bin/bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Error: this script must be run as root (sudo)." >&2
    exit 1
fi

DEVICE=""
IMAGE="ghcr.io/fredolx/proper-bazzite-ps5:latest"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --device|-d)
            DEVICE="$2"
            shift 2
            ;;
        --image|-i)
            IMAGE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 <device> [image] or $0 --device <device> [--image <image>]"
            exit 0
            ;;
        *)
            if [ -z "$DEVICE" ]; then
                DEVICE="$1"
                shift
            elif [ "$IMAGE" = "ghcr.io/fredolx/proper-bazzite-ps5:latest" ]; then
                IMAGE="$1"
                shift
            else
                echo "Unknown argument: $1" >&2
                exit 1
            fi
            ;;
    esac
done

if [ -z "$DEVICE" ]; then
    echo "Error: target device not specified." >&2
    echo "Usage: $0 /dev/sdX [image_ref]" >&2
    exit 1
fi

if [ ! -b "$DEVICE" ]; then
    echo "Error: $DEVICE is not a valid block device." >&2
    exit 1
fi

read -rp "WARNING: All data on $DEVICE will be permanently ERASED. Continue? [y/N] " CONFIRM
if [[ ! "$CONFIRM" =~ ^[yY]([eE][sS])?$ ]]; then
    echo "Aborted."
    exit 1
fi

umount "${DEVICE}"* 2>/dev/null || true

echo "Installing bootc container image $IMAGE to $DEVICE..."
podman run --rm --privileged \
    --pid=host \
    -v /dev:/dev \
    -v /var/lib/containers:/var/lib/containers \
    "$IMAGE" \
    bootc install to-disk --generic-image --wipe=always "$DEVICE"

udevadm settle 2>/dev/null || sleep 2

if [[ "$DEVICE" =~ [0-9]$ ]]; then
    BOOT_PART="${DEVICE}p1"
else
    BOOT_PART="${DEVICE}1"
fi

if [ -b "$BOOT_PART" ]; then
    MOUNT_BOOT="$(mktemp -d)"
    mount "$BOOT_PART" "$MOUNT_BOOT"
    
    if [ ! -f "$MOUNT_BOOT/bzImage" ] && [ -f "$MOUNT_BOOT/vmlinuz" ]; then
        cp "$MOUNT_BOOT/vmlinuz" "$MOUNT_BOOT/bzImage"
    fi
    
    if [ ! -f "$MOUNT_BOOT/cmdline.txt" ]; then
        echo "rw quiet console=tty0" > "$MOUNT_BOOT/cmdline.txt"
    fi
    
    sync
    umount "$MOUNT_BOOT"
    rm -rf "$MOUNT_BOOT"
fi

echo "Installation complete on $DEVICE."
