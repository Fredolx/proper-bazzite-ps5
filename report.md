# Project Report: `proper-bazzite-ps5`

This report summarizes the entire development lifecycle, explicit user requirements and architectural constraints, technical challenges diagnosed and solved, and the final state of the **`proper-bazzite-ps5`** repository.

---

## 1. Project Objective & Vision

The goal of this project is to create a modern, clean, container-native **Bazzite Linux distribution for the PlayStation 5 (Oberon SoC)**:
* Built directly on top of upstream **`ghcr.io/ublue-os/bazzite-deck:stable`**.
* Powered by the custom **Linux 7.1.7 kernel** with PS5 hardware patches, NXP IW620 Wi-Fi/Bluetooth drivers, and Oberon fan/boost control.
* Utilizing a modern, automated **two-stage CI/CD pipeline** on GitHub Container Registry (GHCR):
  1. `kernel-build.yml`: Compiles the PS5 kernel, Wi-Fi modules, and `ps5_control` hardware management binary into RPMs.
  2. `image-build.yml`: Injects the custom kernel via `rpm-ostree override replace`, applies hardware configurations, generates a bootable initramfs, and publishes the final bootc image.

---

## 2. Explicit User Requirements & Constraints

Throughout the project, several strict requirements and preferences were established:

1. **Strict Commit & Push Policy**:
   * *Requirement*: `"no never make commits for me"`.
   * *Implementation*: The assistant never executes `git commit` or `git push` autonomously; all code modifications remain staged/unstaged in the working tree for user review and manual commit.

2. **Comment Policy**:
   * *Requirement*: Zero code comments in new files; preserve authorized explanatory comments in existing packaging helpers.
   * *Implementation*: Zero comments across all new configuration files, systemd units, udev rules, and scripts.

3. **Submodule Architecture**:
   * *Requirement*: Submodules must live in `external/` (not `submodules/`).
   * *Implementation*: Configured `external/ps5-linux-patches`, `external/ps5-linux-mwifiex`, and `external/ps5-linux-tools`.

4. **License Selection**:
   * *Requirement*: Use GNU General Public License v2.0 (`GPL-2.0`).
   * *Implementation*: Downloaded official GPL-2.0 text into `LICENSE`.

5. **Remote Desktop Access (KRDP)**:
   * *Requirement*: Remote desktop must use KDE's native **KRDP** and be enabled automatically on boot for desktop sessions.
   * *Implementation*: Installed `krdp`, enabled `app-org.kde.krdpserver.service` via `99-krdp.preset`, and pre-configured port 3389 in `system_files/etc/xdg/krdprc`.

6. **Clean Architecture & Simplicity**:
   * *Requirement*: Avoid inline script generation, over-engineered error handling, or redundant wrapper bloat.
   * *Implementation*: Separated build-time packaging scripts (`packaging/`) from runtime system drop-ins (`system_files/`).

---

## 3. Technical Problems Identified & Solved

### A. CI/CD & Registry Issues
1. **GitHub Actions OCI Repository Casing**:
   * *Problem*: GHCR strictly requires lowercase repository names (e.g. `fredolx`), but `github.repository_owner` evaluated to `Fredolx`, failing authentication and push.
   * *Fix*: Added `REGISTRY_OWNER=$(echo "${{ github.repository_owner }}" | tr '[:upper:]' '[:lower:]')` in both workflow files.
2. **OverlayFS Layer Limit (`max depth exceeded`)**:
   * *Problem*: The default GitHub Actions Docker daemon hit the 128-layer limit on OverlayFS during multi-stage image extraction.
   * *Fix*: Added `docker/setup-buildx-action@v3` to workflows to run the containerized BuildKit daemon.
3. **Workflow Run Gating**:
   * *Problem*: `workflow_run` on kernel completion triggered the image build even when kernel builds failed.
   * *Fix*: Added `if: ${{ github.event_name != 'workflow_run' || github.event.workflow_run.conclusion == 'success' }}` to `image-build.yml`.

### B. Filesystem & Build Quirks
4. **OSTree `/usr/local` Symlink Conflict**:
   * *Problem*: In Fedora Atomic/Bazzite, `/usr/local` is a symlink to `/var/usrlocal`. Copying build files to `/usr/local/sbin/` broke container layer extraction.
   * *Fix*: Moved all executable scripts and binaries to `/usr/bin/`.
5. **Dracut `/root` Broken Symlink**:
   * *Problem*: In Bazzite, `/root` is a symlink to `/var/roothome`. During container builds without host state, `dracut-install` failed trying to copy `/root`.
   * *Fix*: Added `mkdir -p /var/roothome` before invoking `dracut`.
6. **Generic Hardware Initramfs (`--no-hostonly`)**:
   * *Problem*: Default `dracut` builds an initramfs tailored to the host VM/runner hardware rather than PS5 hardware.
   * *Fix*: Added `--no-hostonly` and explicit kernel version discovery to `packaging/build-initramfs.sh`.

### C. PS5 Hardware, Graphics & Cooling Fixes
7. **PS5 Oberon AMDGPU Firmware Decompression (`cyan_skillfish`)**:
   * *Problem*: Fedora/Bazzite compresses GPU firmware as `.xz`. The PS5 `amdgpu` kernel patch writes into the `request_firmware()` buffer during early init to strip Sony's signature header. Because `.xz` decompression maps pages read-only (`PAGE_KERNEL_RO`), the write triggered a kernel oops on boot and black-screened.
   * *Fix*: Created `packaging/decompress-gpu-firmware.sh` to decompress all `cyan_skillfish*.xz` blobs to raw `.bin` and resolve duplicate symlinks.
8. **AMDGPU Display Reprobe via Systemd**:
   * *Problem*: Running `( sleep 3; echo detect > ... ) &` directly inside a udev `RUN+=` rule was killed immediately by `systemd-udevd`'s cgroup cleanup before 3 seconds elapsed.
   * *Fix*: Replaced `RUN+=` with `TAG+="systemd", ENV{SYSTEMD_WANTS}="ps5-amdgpu-reprobe.service"` and a dedicated systemd oneshot unit with `ExecStartPre=/usr/bin/sleep 3`.
9. **Fan Regulation & Performance Boost (`ps5_control`)**:
   * *Problem*: Without active userspace fan control (`/dev/icc`) and boost management (`/dev/mp1`), the Oberon APU risked thermal throttling or operating at base frequencies.
   * *Fix*: Added `external/ps5-linux-tools` submodule, compiled `ps5_control` inside `build-kernel.sh`, packaged it into the kernel RPM, and created `ps5fan.service` and `ps5boost.service`.
10. **Fast Wi-Fi Latency & Stability**:
    * *Problem*: Power-saving (`ps_mode=2`) and deep-sleep (`auto_ds=2`) modes caused high packet latency and command timeouts on the PS5 NXP IW620 chip.
    * *Fix*: Configured `moal.conf` with `ps_mode=0 auto_ds=0 amsdu_disable=0`.
11. **Native `bootc` NVMe Flashing**:
    * *Problem*: Flat `tar` extraction broke OSTree stateroot and atomic updates (`bootc update`).
    * *Fix*: Upgraded `packaging/flash-nvme.sh` to invoke `bootc install to-disk --generic-image --wipe=always` inside a privileged container, preserving full bootc/OSTree compliance.

---

## 4. Final Architecture & Repository Layout

```text
proper-bazzite-ps5/
├── .github/
│   └── workflows/
│       ├── kernel-build.yml                 (Compiles Linux 7.1.7 + NXP Wi-Fi + ps5_control -> GHCR)
│       └── image-build.yml                  (Builds Bazzite PS5 Container -> GHCR)
├── .gitignore
├── .gitmodules
├── Dockerfile                               (Streamlined OCI container image definition)
├── LICENSE                                  (GNU General Public License v2.0)
├── README.md
├── external/
│   ├── ps5-linux-mwifiex                    (NXP IW620 Wi-Fi/Bluetooth driver patches)
│   ├── ps5-linux-patches                    (Linux 7.1.7 kernel patches & config)
│   └── ps5-linux-tools                      (Oberon fan & boost hardware control)
├── packaging/
│   ├── Dockerfile.kernel                    (Scratch packaging container for RPMs)
│   ├── build-kernel.sh                      (Kernel, Wi-Fi module & ps5_control compilation script)
│   ├── build-initramfs.sh                   (Initramfs builder with dracut)
│   ├── decompress-gpu-firmware.sh           (GPU firmware .xz decompressor)
│   ├── fix-gamescope-desktop-alias.sh       (Wayland desktop alias linker)
│   ├── flash-nvme.sh                        (Native bootc target disk installer)
│   └── kernel-ps5.spec                      (Binary RPM specification)
└── system_files/                            (Runtime rootfs overlay)
    ├── etc/
    │   ├── dracut.conf.d/10-ps5.conf
    │   ├── modprobe.d/
    │   │   ├── moal.conf                    (Low-latency IW620 driver options)
    │   │   └── ps5-amdgpu.conf
    │   ├── modules-load.d/moal.conf
    │   ├── NetworkManager/conf.d/00-no-iwd.conf
    │   ├── systemd/
    │   │   ├── system/
    │   │   │   ├── ps5-amdgpu-reprobe.service
    │   │   │   ├── ps5-bt-quiet.service
    │   │   │   ├── ps5-stage-firmware.service
    │   │   │   ├── ps5boost.service
    │   │   │   └── ps5fan.service
    │   │   └── user-preset/
    │   │       └── 99-krdp.preset
    │   ├── udev/rules.d/70-ps5-amdgpu-reprobe.rules
    │   └── xdg/krdprc
    └── usr/
        ├── bin/
        │   ├── ps5-amdgpu-reprobe
        │   ├── ps5-bt-quiet
        │   └── ps5-stage-firmware
        └── share/gamescope/scripts/ps5-display.lua
```
