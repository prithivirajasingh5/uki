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

# Clean package cache
rm -rf "$ROOTFS/var/cache/apt/archives"/*.deb \
       "$ROOTFS/var/lib/apt/lists"/*

echo "Done: $ROOTFS"
