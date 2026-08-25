ARG KERNEL_IMAGE=ghcr.io/fredolx/proper-bazzite-ps5-kernel:latest
FROM ${KERNEL_IMAGE} AS kernel
FROM ghcr.io/ublue-os/bazzite-deck:stable

COPY --from=kernel /rpms/ /tmp/rpms/

RUN rpm-ostree override replace /tmp/rpms/*.rpm && \
    rpm-ostree install krdp && \
    rm -rf /tmp/rpms

COPY system_files/ /

RUN if [ -d /usr/lib/firmware/amdgpu ]; then \
        cd /usr/lib/firmware/amdgpu && \
        for f in cyan_skillfish*.xz; do \
            [ -e "$f" ] || [ -L "$f" ] || continue; \
            if [ -L "$f" ]; then \
                tgt=$(readlink "$f"); \
                rm -f "$f"; \
                ln -sf "${tgt%.xz}" "${f%.xz}"; \
            else \
                xz -dc "$f" > "${f%.xz}"; \
                rm -f "$f"; \
            fi; \
        done; \
    fi

RUN for cand in plasma.desktop plasma-steamos-wayland-oneshot.desktop; do \
        if [ -e "/usr/share/wayland-sessions/$cand" ]; then \
            ln -sf "$cand" /usr/share/wayland-sessions/desktop.desktop; \
            break; \
        fi; \
    done

RUN systemctl --global enable app-org.kde.krdpserver.service 2>/dev/null || true && \
    systemctl enable ps5-stage-firmware.service ps5-bt-quiet.service 2>/dev/null || true

RUN mkdir -p /var/roothome && \
    KVER=$(ls -1t /usr/lib/modules | head -n1) && \
    dracut --force --no-hostonly --kver "$KVER" "/usr/lib/modules/$KVER/initramfs.img" && \
    cp "/usr/lib/modules/$KVER/initramfs.img" "/boot/initramfs-$KVER.img" 2>/dev/null || true

LABEL "containers.bootc"="1"
