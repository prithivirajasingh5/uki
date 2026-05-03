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
    kmod             # provides modprobe/depmod for the rescue shell
    dbus             # required by iwd — provides dbus.socket/dbus.service
    systemd-sysv     # provides poweroff/reboot/halt/shutdown as systemctl symlinks
    udev             # auto-loads kernel modules from pci/usb aliases on boot
    iputils-ping     # ping
    findutils        # find
    isc-dhcp-client  # dhclient — request an IP via DHCP on any interface
    nano             # nano text editor
    procps           # ps, free
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

# debootstrap --variant=minbase skips the postinst hooks that would normally
# enable services via deb-systemd-helper. Enable iwd explicitly so it starts
# on boot and manages any wifi interface that udev hands it.
systemctl --root="$ROOTFS" enable iwd

# Tell iwd to run its own DHCP client and process IPv6 router advertisements
# after association. Without this, iwd only handles layer 2 (WiFi association)
# and the kernel only generates a link-local IPv6 address — no IPv4, no global IPv6.
mkdir -p "$ROOTFS/etc/iwd"
cat > "$ROOTFS/etc/iwd/main.conf" <<'EOF'
[General]
EnableNetworkConfiguration=true

[Network]
EnableIPv6=true
EOF

# Auto-login root on tty1 (physical console) and ttyS0 (QEMU serial).
for tty in tty1 ttyS0; do
    dir="$ROOTFS/etc/systemd/system/getty@${tty}.service.d"
    mkdir -p "$dir"
    printf '[Service]\nExecStart=\nExecStart=-/sbin/agetty --autologin root --noclear %%I $TERM\n' \
        > "$dir/autologin.conf"
done

# Ensure sbin paths are in PATH — minbase Debian shells often omit /usr/sbin
echo 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' \
    > "$ROOTFS/etc/profile.d/path.sh"

# Kernel modules — must match the kernel embedded in the UKI.
# The UKI build picks /boot/vmlinuz-$(KVER), so we copy the matching modules
# from the build host. Without these, udev can't load any drivers after
# switch_root (no NVMe, no NIC, no USB storage).
KVER=$(uname -r)
if [ -d "/lib/modules/$KVER" ]; then
    echo "Copying kernel modules ($KVER) — this may take a minute..."
    mkdir -p "$ROOTFS/lib/modules"
    cp -a "/lib/modules/$KVER" "$ROOTFS/lib/modules/"
    # Drop modules that are useless in a text-console rescue image.
    # GPU: no display compositor; sound: no audio; media: no webcam/DVB.
    KMOD="$ROOTFS/lib/modules/$KVER/kernel"
    rm -rf "$KMOD/drivers/gpu" "$KMOD/sound" "$KMOD/drivers/media"
    depmod -b "$ROOTFS" "$KVER"
else
    echo "warning: /lib/modules/$KVER not found — NVMe/NIC drivers will not load" >&2
fi

# Firmware blobs — required for WiFi (regulatory.db, iwlwifi-*.ucode, etc.)
# and many NIC controllers. Copy from the build host then strip firmware that
# a text-console rescue system will never use, to keep the EFI image small.
if [ -d /lib/firmware ]; then
    echo "Copying firmware files — this may take a minute..."
    mkdir -p "$ROOTFS/lib/firmware"
    cp -a /lib/firmware/. "$ROOTFS/lib/firmware/"
    FW="$ROOTFS/lib/firmware"
    # GPU firmware — rescue runs on a text console, no display driver needed
    rm -rf "$FW/nvidia" "$FW/amdgpu" "$FW/radeon" "$FW/i915" "$FW/xe"
    # Enterprise/datacenter NICs — Mellanox InfiniBand, Marvell HBAs,
    # Netronome SmartNICs, QLogic qed, NXP dpaa2: not in consumer rescue targets
    rm -rf "$FW/mellanox" "$FW/mrvl" "$FW/netronome" "$FW/qed" "$FW/dpaa2"
    # Qualcomm mobile SoC firmware — not relevant on x86 rescue hardware
    rm -rf "$FW/qcom"
    # Audio codec firmware — no sound needed in rescue
    rm -rf "$FW/cirrus"
fi

# Clean package cache
rm -rf "$ROOTFS/var/cache/apt/archives"/*.deb \
       "$ROOTFS/var/lib/apt/lists"/*

echo "Done: $ROOTFS"
