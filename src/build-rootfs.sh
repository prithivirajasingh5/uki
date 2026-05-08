#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOTFS="${ROOTFS:-work/full/rootfs}"
VARIANT="${VARIANT:-full}"

if [ "$(id -u)" -ne 0 ]; then
    echo "error: must run as root (needed for debootstrap)" >&2
    exit 1
fi

mkdir -p "$ROOTFS"

# ── packages present in both variants ────────────────────────────────────────
PACKAGES_COMMON=(
    # Core shell + init
    bash
    util-linux          # lsblk, blkid, fdisk, mount, losetup, etc.

    # Partitioning + filesystems
    parted
    gdisk
    btrfs-progs
    nvme-cli
    e2fsprogs           # ext4: mkfs.ext4, fsck.ext4
    dosfstools          # FAT/EFI: mkfs.fat, fsck.fat
    ntfs-3g             # NTFS read/write
    exfatprogs          # exFAT

    # EFI boot management
    efibootmgr
    grub-efi-amd64-bin  # grub-install for EFI repair inside chroot

    # Editors + pager
    nano
    vim-tiny            # vi
    less

    # Hardware inspection (needed in mini to diagnose PCI/USB devices)
    pciutils            # lspci
    usbutils            # lsusb
    lshw                # full hardware inventory

    # File tools
    findutils           # find
    tree                # directory tree listing

    # System services
    kmod                # modprobe/depmod
    dbus                # required by systemd
    systemd-sysv        # poweroff, reboot, halt
    udev                # module autoload on boot
    squashfs-tools      # unsquashfs — used by init and available in rescue shell
    procps              # ps, free
)

# ── packages only in the full variant ────────────────────────────────────────
PACKAGES_FULL=(
    # Filesystems
    xfsprogs            # XFS: xfs_repair, mkfs.xfs

    # Networking + file transfer
    curl
    dmidecode           # BIOS/DMI tables — RAM slots, serial numbers

    xz-utils            # decompress .xz archives

    # LVM + LUKS
    lvm2
    cryptsetup

    # Disk health + data recovery
    smartmontools       # smartctl
    testdisk            # recover lost partitions
    gddrescue           # ddrescue — image around bad sectors

    # WiFi + networking
    iwd
    iproute2
    isc-dhcp-client     # dhclient
    iputils-ping
    traceroute
    netcat-openbsd
    tcpdump
    ethtool
    bind9-dnsutils      # dig, nslookup

    # Remote access + file sync
    openssh-client
    rsync

    # Process + debug
    htop
    lsof
    strace

    # Extra tools
    file
)

if [ "$VARIANT" = "mini" ]; then
    PACKAGES=("${PACKAGES_COMMON[@]}")
else
    PACKAGES=("${PACKAGES_COMMON[@]}" "${PACKAGES_FULL[@]}")
fi

IFS=',' INCLUDE="${PACKAGES[*]}"

echo "==> Bootstrapping Debian ($VARIANT) into $ROOTFS ..."
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

# nvme-cli ships nvmf-autoconnect.service which probes for NVMe-oF targets on
# boot — always fails in a rescue context, so mask it.
systemctl --root="$ROOTFS" mask nvmf-autoconnect.service

# Auto-login root on tty1 (physical console) and ttyS0 (QEMU serial).
for tty in tty1 ttyS0; do
    dir="$ROOTFS/etc/systemd/system/getty@${tty}.service.d"
    mkdir -p "$dir"
    # shellcheck disable=SC2016  # $TERM is a literal string for the systemd unit, not a shell variable
    printf '[Service]\nExecStart=\nExecStart=-/sbin/agetty --autologin root --noclear %%I $TERM\n' \
        > "$dir/autologin.conf"
done

# Ensure sbin paths are in PATH — minbase Debian shells often omit /usr/sbin
echo 'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' \
    > "$ROOTFS/etc/profile.d/path.sh"

# C.UTF-8 is built into glibc — no locales package or locale-gen needed.
# Without this, less and other tools treat multi-byte UTF-8 as binary.
printf 'export LANG=C.UTF-8\nexport LC_ALL=C.UTF-8\n' \
    > "$ROOTFS/etc/profile.d/locale.sh"
printf 'LANG=C.UTF-8\n' > "$ROOTFS/etc/default/locale"

# Mute the terminal bell entirely:
#   1. blacklist pcspkr so the PC speaker driver never loads
#   2. tell readline to never emit BEL (covers bash tab-complete, end-of-history)
#   3. set LESS=-q so the pager doesn't beep on attempted scroll past EOF
echo 'blacklist pcspkr' > "$ROOTFS/etc/modprobe.d/nobeep.conf"
printf 'set bell-style none\n' >> "$ROOTFS/etc/inputrc"
printf 'export LESS="-q"\n' > "$ROOTFS/etc/profile.d/nobell.sh"

# readme command — type 'readme' at the rescue shell for a quick reference
if [ "$VARIANT" = "mini" ]; then
    install -m 0755 "$SCRIPT_DIR/rescue-readme-mini" "$ROOTFS/usr/local/bin/readme"
else
    install -m 0755 "$SCRIPT_DIR/rescue-readme" "$ROOTFS/usr/local/bin/readme"
fi

# ── kernel modules ───────────────────────────────────────────────────────────
KVER=$(uname -r)
if [ "$VARIANT" = "full" ]; then
    if [ -d "/lib/modules/$KVER" ]; then
        echo "Copying kernel modules ($KVER) — this may take a minute..."
        mkdir -p "$ROOTFS/lib/modules"
        cp -a "/lib/modules/$KVER" "$ROOTFS/lib/modules/"
        KMOD="$ROOTFS/lib/modules/$KVER/kernel"
        rm -rf "$KMOD/drivers/gpu" "$KMOD/sound" "$KMOD/drivers/media"
        depmod -b "$ROOTFS" "$KVER"
    else
        echo "warning: /lib/modules/$KVER not found — NVMe/NIC drivers will not load" >&2
    fi
else
    # Mini: copy only storage drivers so NVMe/SATA drives appear in /dev.
    # udev will autoload them via MODALIAS on boot; modprobe also works manually.
    if [ -d "/lib/modules/$KVER" ]; then
        echo "Copying storage kernel modules ($KVER)..."
        mkdir -p "$ROOTFS/lib/modules/$KVER/kernel/drivers"
        # Module metadata files (modules.dep, modules.alias, modules.builtin …)
        find "/lib/modules/$KVER" -maxdepth 1 -type f \
            -exec cp {} "$ROOTFS/lib/modules/$KVER/" \;
        # Driver directories: NVMe, AHCI/SATA, SCSI layer (dep of ata), USB storage
        for drv in nvme ata scsi mmc usb/storage usb/host; do
            src="/lib/modules/$KVER/kernel/drivers/$drv"
            [ -d "$src" ] || continue
            dest="$ROOTFS/lib/modules/$KVER/kernel/drivers/$drv"
            mkdir -p "$(dirname "$dest")"
            cp -a "$src" "$dest"
        done
        # Enterprise HBA / SAN drivers — never needed on personal hardware.
        # These subdirs can total 100–200 MB on a desktop kernel; strip them to
        # keep RAM usage down. Consumer SATA still works via sd_mod + ahci.
        for hba in lpfc qla2xxx qla4xxx mpt2sas mpt3sas megaraid megaraid_sas \
                   aacraid hpsa pm80xx pm8001 aic7xxx aic94xx csiostor \
                   be2iscsi bnx2i cxgb4i iscsi_tcp libiscsi fcoe libfc; do
            rm -rf "$ROOTFS/lib/modules/$KVER/kernel/drivers/scsi/$hba"
        done

        # Filesystem modules: btrfs.ko + its dependencies (raid6_pq, xor, blake2b).
        # Copying kernel/lib and kernel/crypto wholesale (~920 KB) avoids hardcoding
        # specific filenames that change across kernel versions.
        for mod_dir in fs/btrfs lib crypto; do
            src="/lib/modules/$KVER/kernel/$mod_dir"
            [ -d "$src" ] || continue
            dest="$ROOTFS/lib/modules/$KVER/kernel/$mod_dir"
            mkdir -p "$(dirname "$dest")"
            cp -a "$src" "$dest"
        done
        depmod -b "$ROOTFS" "$KVER"
    else
        echo "warning: /lib/modules/$KVER not found — NVMe drivers will not load" >&2
    fi
fi

# ── full-only: WiFi, firmware ─────────────────────────────────────────────────
if [ "$VARIANT" = "full" ]; then
    # Enable iwd so it starts on boot and manages any wifi interface
    systemctl --root="$ROOTFS" enable iwd

    # iwd built-in DHCP + IPv6 — without this, iwd only handles layer 2
    mkdir -p "$ROOTFS/etc/iwd"
    cat > "$ROOTFS/etc/iwd/main.conf" <<'EOF'
[General]
EnableNetworkConfiguration=true

[Network]
EnableIPv6=true
EOF

    # Replace the dead systemd-resolved stub with public DNS resolvers
    rm -f "$ROOTFS/etc/resolv.conf"
    cat > "$ROOTFS/etc/resolv.conf" <<'EOF'
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF

    # Firmware — WiFi, NIC controllers, etc.
    if [ -d /lib/firmware ]; then
        echo "Copying firmware files — this may take a minute..."
        mkdir -p "$ROOTFS/lib/firmware"
        cp -a /lib/firmware/. "$ROOTFS/lib/firmware/"
        FW="$ROOTFS/lib/firmware"
        rm -rf "$FW/nvidia" "$FW/amdgpu" "$FW/radeon" "$FW/i915" "$FW/xe"
        rm -rf "$FW/mellanox" "$FW/mrvl" "$FW/netronome" "$FW/qed" "$FW/dpaa2"
        rm -rf "$FW/qcom"
        rm -rf "$FW/cirrus"
    fi
fi

# ── mini-only: strip docs, man pages, and locale data ────────────────────────
# These directories serve no purpose in a rescue shell and can add 50–150 MB
# across a typical Debian package set. LANG=C.UTF-8 is glibc-builtin so no
# locale files are needed.
if [ "$VARIANT" = "mini" ]; then
    rm -rf "$ROOTFS/usr/share/doc"
    rm -rf "$ROOTFS/usr/share/man"
    rm -rf "$ROOTFS/usr/share/info"
    rm -rf "$ROOTFS/usr/share/groff"
    find "$ROOTFS/usr/share/locale" -mindepth 1 -maxdepth 1 -type d \
        -exec rm -rf {} +
fi

# Clean package cache
rm -rf "$ROOTFS/var/cache/apt/archives"/*.deb \
       "$ROOTFS/var/lib/apt/lists"/*

echo "Done: $ROOTFS"
