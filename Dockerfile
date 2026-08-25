ARG KERNEL_IMAGE=ghcr.io/fredolx/proper-bazzite-ps5-kernel:latest
FROM ${KERNEL_IMAGE} AS kernel
FROM ghcr.io/ublue-os/bazzite-deck:stable

COPY --from=kernel /rpms/ /tmp/rpms/

RUN rpm-ostree override replace /tmp/rpms/*.rpm && \
    rpm-ostree install krdp && \
    rm -rf /tmp/rpms

COPY system_files/ /

RUN systemctl --global enable plasma-krdp.service 2>/dev/null || true

RUN mkdir -p /var/roothome && \
    KVER=$(ls -1t /usr/lib/modules | head -n1) && \
    dracut --force --no-hostonly --kver "$KVER" "/usr/lib/modules/$KVER/initramfs.img" && \
    cp "/usr/lib/modules/$KVER/initramfs.img" "/boot/initramfs-$KVER.img" 2>/dev/null || true

LABEL "containers.bootc"="1"
