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
for loop in $(losetup -j "$OUTPUT_FILE" 2>/dev/null | cut -d: -f1); do
    losetup -d "$loop" 2>/dev/null || true
done
rm -f "$OUTPUT_FILE"
truncate -s 25G "$OUTPUT_FILE"

echo "Building bootable disk image with bootc..."
podman run --rm --privileged \
    --pid=host \
    --security-opt label=disable \
    -v /dev:/dev \
    -v /var/lib/containers:/var/lib/containers \
    -v "$(dirname "$OUTPUT_FILE")":/output:z \
    "$IMAGE" \
    bootc install to-disk --generic-image --wipe --via-loopback "/output/$(basename "$OUTPUT_FILE")" --filesystem btrfs

echo "Configuring PS5 bootloader files (bzImage, initramfs, vram.txt, cmdline.txt, firmware)..."
LOOPDEV=$(losetup -fP --show "$OUTPUT_FILE")
udevadm settle 2>/dev/null || sleep 2

MOUNT_BOOT="$(mktemp -d)"
mount "${LOOPDEV}p2" "$MOUNT_BOOT"

CID="$(podman create "$IMAGE")"
podman cp "$CID:/usr/lib/modules" "$MOUNT_BOOT/.temp_k"
K_DIR="$(ls -1td "$MOUNT_BOOT"/.temp_k/* | head -n1)"
cp "$K_DIR/vmlinuz" "$MOUNT_BOOT/bzImage"
cp "$K_DIR/initramfs.img" "$MOUNT_BOOT/initramfs.img"
cp "$K_DIR/initramfs.img" "$MOUNT_BOOT/initrd.img"
rm -rf "$MOUNT_BOOT/.temp_k"

mkdir -p "$MOUNT_BOOT/lib/nxp"
podman cp "$CID:/usr/lib/firmware/nxp" "$MOUNT_BOOT/lib/.temp_nxp" 2>/dev/null || true
if [ -d "$MOUNT_BOOT/lib/.temp_nxp" ]; then
    for fw in "$MOUNT_BOOT/lib/.temp_nxp"/*iw620*; do
        [ -e "$fw" ] || continue
        if [[ "$fw" == *.xz ]]; then
            xz -dc "$fw" > "$MOUNT_BOOT/lib/nxp/$(basename "${fw%.xz}")"
        else
            cp "$fw" "$MOUNT_BOOT/lib/nxp/"
        fi
    done
    rm -rf "$MOUNT_BOOT/lib/.temp_nxp"
fi
podman rm "$CID" >/dev/null 2>&1 || true

echo "0x20000000" > "$MOUNT_BOOT/vram.txt"
echo "root=LABEL=root rw rootwait console=ttyTitania0 console=tty0 video=DP-1:1920x1080@60 mitigations=off idle=halt preempt=full selinux=0" > "$MOUNT_BOOT/cmdline.txt"

cat <<'KEXEC' > "$MOUNT_BOOT/kexec.sh"
#!/bin/sh
set -e
BOOT=/boot/efi
kexec -l "$BOOT/bzImage" --initrd="$BOOT/initrd.img" --command-line="$(cat $BOOT/cmdline.txt)"
kexec -e
KEXEC
chmod +x "$MOUNT_BOOT/kexec.sh"

sync
umount "$MOUNT_BOOT"
rmdir "$MOUNT_BOOT"
losetup -d "$LOOPDEV"

echo "=========================================================="
echo "Done! Disk image: $OUTPUT_FILE"
echo "Flash with: sudo dd if=$OUTPUT_FILE of=/dev/sdX bs=4M status=progress conv=fsync"
echo "=========================================================="
