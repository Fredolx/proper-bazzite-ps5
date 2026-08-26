ARG KERNEL_IMAGE=ghcr.io/fredolx/proper-bazzite-ps5-kernel:latest
FROM ${KERNEL_IMAGE} AS kernel
FROM ghcr.io/ublue-os/bazzite-deck:stable

COPY --from=kernel /rpms/ /tmp/rpms/

RUN rpm-ostree override replace /tmp/rpms/*.rpm && \
    rpm-ostree install krdp && \
    rm -rf /tmp/rpms /etc/yum.repos.d/terra*.repo /etc/dnf/repos.override.d/* && \
    cp -rf /usr/share/distribution-gpg-keys/*/* /etc/pki/rpm-gpg/ 2>/dev/null || true

COPY system_files/ /
COPY packaging/decompress-gpu-firmware.sh \
     packaging/fix-gamescope-desktop-alias.sh \
     packaging/build-initramfs.sh \
     /tmp/

RUN /tmp/decompress-gpu-firmware.sh && \
    /tmp/fix-gamescope-desktop-alias.sh && \
    systemctl --global enable app-org.kde.krdpserver.service 2>/dev/null || true && \
    systemctl enable ps5-stage-firmware.service ps5-bt-quiet.service 2>/dev/null || true && \
    /tmp/build-initramfs.sh && \
    rm -rf /tmp/*

LABEL "containers.bootc"="1"
