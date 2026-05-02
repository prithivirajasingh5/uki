#!/bin/bash
set -euo pipefail

ROOTFS=work/rootfs

if [ "$(id -u)" -ne 0 ]; then
    echo "error: must run as root (needed for debootstrap)" >&2
    exit 1
fi

mkdir -p "$ROOTFS"

PACKAGES=(
    bash
    util-linux
    pciutils
    usbutils
    curl
    parted
    gdisk
    btrfs-progs
    nvme-cli
    iwd
    iproute2
    openssh-client
    squashfs-tools   # provides unsquashfs inside the running rescue system
)

IFS=',' INCLUDE="${PACKAGES[*]}"

echo "Bootstrapping Debian into $ROOTFS ..."
debootstrap \
    --variant=minbase \
    --include="$INCLUDE" \
    stable \
    "$ROOTFS" \
    http://deb.debian.org/debian

# Minimal fstab — avoids mount warnings from systemd
echo "tmpfs / tmpfs defaults 0 0" > "$ROOTFS/etc/fstab"

# Hostname
echo "rescue" > "$ROOTFS/etc/hostname"

# debootstrap --variant=minbase skips postinst scripts that normally create
# /sbin/init -> /lib/systemd/systemd; create it explicitly.
ln -sf /lib/systemd/systemd "$ROOTFS/usr/sbin/init"

# nvme-cli ships nvmf-autoconnect.service which probes for NVMe-oF network
# targets on boot — always fails in a rescue context, so mask it.
systemctl --root="$ROOTFS" mask nvmf-autoconnect.service

# Auto-login root on tty1 (physical console) and ttyS0 (QEMU serial).
for tty in tty1 ttyS0; do
    dir="$ROOTFS/etc/systemd/system/getty@${tty}.service.d"
    mkdir -p "$dir"
    printf '[Service]\nExecStart=\nExecStart=-/sbin/agetty --autologin root --noclear %%I $TERM\n' \
        > "$dir/autologin.conf"
done

# Clean package cache
rm -rf "$ROOTFS/var/cache/apt/archives"/*.deb \
       "$ROOTFS/var/lib/apt/lists"/*

echo "Done: $ROOTFS"
