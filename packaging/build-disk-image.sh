#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

OUTPUT_FILE="$REPO_ROOT/output/proper-bazzite-ps5.raw"
IMAGE="ghcr.io/fredolx/proper-bazzite-ps5:latest"

for arg in "$@"; do
    case "$arg" in
        --local|-l)
            echo "Building kernel and local Bazzite image..."
            [ -z "$(ls -A "$REPO_ROOT/dist-rpms" 2>/dev/null)" ] && "$REPO_ROOT/packaging/build-kernel.sh"
            podman build -t localhost/proper-bazzite-ps5-kernel:local -f "$REPO_ROOT/packaging/Dockerfile.kernel" "$REPO_ROOT"
            podman build -t localhost/proper-bazzite-ps5:local --build-arg KERNEL_IMAGE=localhost/proper-bazzite-ps5-kernel:local -f "$REPO_ROOT/Dockerfile" "$REPO_ROOT"
            IMAGE="localhost/proper-bazzite-ps5:local"
            ;;
        *.raw|*.img)
            OUTPUT_FILE="$arg"
            ;;
        -h|--help)
            echo "Usage: $0 [--local] [output.raw]"
            exit 0
            ;;
    esac
done

if [ "$EUID" -ne 0 ]; then
    echo "Error: this script must be run as root (sudo)." >&2
    exit 1
fi

command -v getenforce >/dev/null 2>&1 && [ "$(getenforce 2>/dev/null)" = "Enforcing" ] && {
    echo "Temporarily setting SELinux to Permissive..."
    setenforce 0 2>/dev/null || true
    trap 'setenforce 1 2>/dev/null || true' EXIT
}

mkdir -p "$(dirname "$OUTPUT_FILE")"
truncate -s 25G "$OUTPUT_FILE"

echo "Building bootable disk image with bootc..."
podman run --rm --privileged \
    --pid=host \
    --security-opt label=disable \
    -v /dev:/dev \
    -v /var/lib/containers:/var/lib/containers \
    -v "$(dirname "$OUTPUT_FILE")":/output:z \
    "$IMAGE" \
    bootc install to-disk --generic-image --via-loopback "/output/$(basename "$OUTPUT_FILE")" --filesystem btrfs

echo "Configuring PS5 bootloader files..."
LOOPDEV=$(losetup -fP --show "$OUTPUT_FILE")
udevadm settle 2>/dev/null || sleep 2

MOUNT_BOOT="$(mktemp -d)"
mount "${LOOPDEV}p2" "$MOUNT_BOOT" 2>/dev/null || mount "${LOOPDEV}p1" "$MOUNT_BOOT"

[ -f "$MOUNT_BOOT/vmlinuz" ] && [ ! -f "$MOUNT_BOOT/bzImage" ] && cp "$MOUNT_BOOT/vmlinuz" "$MOUNT_BOOT/bzImage"
[ ! -f "$MOUNT_BOOT/cmdline.txt" ] && echo "rw quiet console=tty0" > "$MOUNT_BOOT/cmdline.txt"

sync
umount "$MOUNT_BOOT"
rmdir "$MOUNT_BOOT"
losetup -d "$LOOPDEV"

echo "=========================================================="
echo "Done. Output: $OUTPUT_FILE"
echo "=========================================================="
