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
     packaging/build-initramfs.sh \
     /tmp/

RUN /tmp/decompress-gpu-firmware.sh && \
    /tmp/fix-gamescope-desktop-alias.sh && \
    mkdir -p /etc/skel/.config && \
    cp /etc/xdg/krdprc /etc/skel/.config/krdprc && \
    cp /etc/xdg/kxkbrc /etc/skel/.config/kxkbrc && \
    (groupadd -f wheel; groupadd -f video; groupadd -f audio; groupadd -f input; groupadd -f render) && \
    (id ps5 >/dev/null 2>&1 || useradd -m -s /bin/bash -G wheel,video,audio,input,render ps5) && \
    echo "ps5:ps5" | chpasswd && \
    systemctl mask plasma-setup.service 2>/dev/null || true && \
    systemctl --global enable app-org.kde.krdpserver.service 2>/dev/null || true && \
    systemctl enable ps5-stage-firmware.service ps5-bt-quiet.service ps5fan.service ps5boost.service ps5-amdgpu-reprobe.service 2>/dev/null || true && \
    /tmp/build-initramfs.sh && \
    rm -rf /tmp/*

LABEL "containers.bootc"="1"
