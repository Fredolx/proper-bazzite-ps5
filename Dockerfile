ARG KERNEL_IMAGE=ghcr.io/fredolx/proper-bazzite-ps5-kernel:latest
FROM ${KERNEL_IMAGE} AS kernel
FROM ghcr.io/ublue-os/bazzite-deck:stable

COPY --from=kernel /rpms/ /tmp/rpms/

RUN rpm-ostree override replace /tmp/rpms/*.rpm && \
    rpm-ostree install krdp && \
    rm -rf /tmp/rpms

COPY system_files/ /
COPY packaging/decompress-gpu-firmware.sh \
     packaging/fix-gamescope-desktop-alias.sh \
     packaging/setup-default-user.sh \
     packaging/build-initramfs.sh \
     /tmp/

RUN /tmp/decompress-gpu-firmware.sh && \
    /tmp/fix-gamescope-desktop-alias.sh && \
    /tmp/setup-default-user.sh && \
    systemctl --global enable app-org.kde.krdpserver.service 2>/dev/null || true && \
    systemctl enable ps5-stage-firmware.service ps5-sync-boot.service ps5-bt-quiet.service ps5fan.service ps5boost.service ps5-amdgpu-reprobe.service 2>/dev/null || true && \
    /tmp/build-initramfs.sh && \
    rm -rf /tmp/*

LABEL "containers.bootc"="1"
