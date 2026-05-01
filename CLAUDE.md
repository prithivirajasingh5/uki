# Project: uki

## What this is
A build system that produces a single `rescue.efi` Unified Kernel Image which boots entirely from RAM (tmpfs), equipped with disk partitioning, btrfs/nvme support, wifi, and SSH client.

## Stack
Shell scripts (primary), Python (secondary if needed), Makefile for orchestration

## Key tools in the build pipeline
- `debootstrap` — bootstraps a minimal Debian root filesystem
- `squashfs-tools` (`mksquashfs`) — compresses rootfs into a squashfs image
- `systemd-ukify` — assembles kernel + initramfs + cmdline into a PE/EFI binary
- Custom `init` script — mounts tmpfs, unsquashes rootfs into it, calls `switch_root`

## Packages baked into the image
- `parted`, `gdisk` — disk partitioning
- `btrfs-progs` — btrfs filesystem tools
- `nvme-cli` — NVMe drive management
- `iwd` + `iproute2` — wifi (lightweight, no wpa_supplicant daemon needed)
- `openssh-client` — SSH to router/other hosts
- `bash`, `util-linux`, `pciutils`, `usbutils`, `curl`

## Build pipeline (in order)
1. `make rootfs` — debootstrap minimal Debian into `work/rootfs/`
2. `make squashfs` — compress to `work/root.squashfs`
3. `make initramfs` — bundle custom `init` + squashfs into `work/initramfs.cpio.gz`
4. `make uki` — call `ukify` to produce `rescue.efi`
5. `make clean` — remove all intermediate build artifacts

## Commands
- Run: `make all`
- Test: `make test` (runs shellcheck + a QEMU boot smoke test)
- Lint: `shellcheck src/*.sh src/initramfs/init`

## Key directories
- `src/` — build scripts and initramfs `init`
- `src/initramfs/` — files that go into the initramfs (init, udev rules, etc.)
- `tests/` — shellcheck wrappers and QEMU smoke test
- `docs/` — design notes, signing guide, wifi setup

## Rules
- Explain what you're about to do before doing it
- Ask before deleting files or irreversible changes
- Every new feature needs a test
- Keep the initramfs `init` script POSIX sh — no bashisms, it runs before bash is available
- Never hardcode kernel versions — always derive from the running build host or a config variable
