#!/bin/sh
# Steam Deck UI's "Switch to Desktop" button looks for desktop.desktop
# in /usr/share/wayland-sessions/. Link desktop.desktop to plasma.desktop
# so switching from Game Mode to Desktop Mode works out of the box.
set -e

for cand in plasma.desktop plasma-steamos-wayland-oneshot.desktop; do
    if [ -e "/usr/share/wayland-sessions/$cand" ]; then
        ln -sf "$cand" /usr/share/wayland-sessions/desktop.desktop
        break
    fi
done
