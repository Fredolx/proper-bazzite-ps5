#!/bin/sh
# The PS5 kernel patch writes into the request_firmware() buffer to skip
# Sony's signature header (gfx_v10_0_early_init, amdgpu_sdma_init_microcode).
# Firmware loaded from a .xz file is decompressed into pages the kernel
# maps PAGE_KERNEL_RO (read-only), so that write causes a kernel oops and
# /dev/dri never appears. Keep cyan_skillfish GPU firmware uncompressed.
set -e

cd /usr/lib/firmware/amdgpu
for f in cyan_skillfish*.xz; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    if [ -L "$f" ]; then
        tgt=$(readlink "$f")
        rm -f "$f"
        ln -sf "${tgt%.xz}" "${f%.xz}"
    else
        xz -dc "$f" > "${f%.xz}"
        rm -f "$f"
    fi
done
