ARG KERNEL_IMAGE=ghcr.io/fredolx/proper-bazzite-ps5-kernel:latest
FROM ${KERNEL_IMAGE} AS kernel
FROM ghcr.io/ublue-os/bazzite-deck:stable

COPY --from=kernel /rpms/ /tmp/rpms/

RUN rpm-ostree override replace /tmp/rpms/*.rpm && \
    rm -rf /tmp/rpms

RUN dnf install -y krdp && \
    dnf clean all

COPY system_files/ /

RUN systemctl --global enable plasma-krdp.service || true

RUN KVER=$(ls -1t /usr/lib/modules | head -n1) && \
    dracut -f --kver "$KVER" "/usr/lib/modules/$KVER/initramfs.img" && \
    cp "/usr/lib/modules/$KVER/initramfs.img" "/boot/initramfs-$KVER.img" 2>/dev/null || true

LABEL "containers.bootc"="1"
