#!/bin/bash
set -euo pipefail

mkdir -p /etc/skel/.config
cp /etc/xdg/krdprc /etc/skel/.config/krdprc
cp /etc/xdg/kxkbrc /etc/skel/.config/kxkbrc

groupadd -f wheel
groupadd -f video
groupadd -f audio
groupadd -f input
groupadd -f render

if ! id ps5 >/dev/null 2>&1; then
    useradd -m -s /bin/bash -G wheel,video,audio,input,render ps5
fi

echo "ps5:ps5" | chpasswd
systemctl mask plasma-setup.service 2>/dev/null || true
