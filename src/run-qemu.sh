#!/bin/bash
set -euo pipefail

OUTPUT="${OUTPUT:-rescue-full.efi}"
EFI_IMG="${EFI_IMG:-work/full/efi.img}"
OVMF_CODE=/usr/share/OVMF/OVMF_CODE_4M.fd
OVMF_VARS_TEMPLATE=/usr/share/OVMF/OVMF_VARS_4M.fd
OVMF_VARS=/tmp/uki-ovmf-vars.fd

if [ ! -f "$OUTPUT" ]; then
    echo "error: $OUTPUT not found — run 'make uki' first" >&2
    exit 1
fi

if [ ! -f "$OVMF_CODE" ] || [ ! -f "$OVMF_VARS_TEMPLATE" ]; then
    echo "error: OVMF_CODE_4M.fd / OVMF_VARS_4M.fd not found — install ovmf package" >&2
    exit 1
fi

for cmd in qemu-system-x86_64 parted mkfs.vfat losetup; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "error: $cmd not found — install qemu-system-x86 dosfstools util-linux" >&2
        exit 1
    fi
done

# Rebuild the disk image only when rescue.efi is newer than the last image.
# OVMF requires a real GPT disk with an EFI System Partition.
if [ ! -f "$EFI_IMG" ] || [ "$OUTPUT" -nt "$EFI_IMG" ]; then
    echo "Building EFI boot image..."
    # Size: UKI size rounded up to the next 32M boundary, plus 2M overhead
    EFI_SIZE=$(du -m "$OUTPUT" | cut -f1)
    DISK_MB=$(( ((EFI_SIZE + 32) / 32 + 1) * 32 ))
    PART_END_MB=$(( DISK_MB - 1 ))

    rm -f "$EFI_IMG"
    dd if=/dev/zero of="$EFI_IMG" bs=1M count="$DISK_MB" status=none
    parted -s "$EFI_IMG" mklabel gpt mkpart ESP fat32 1MiB "${PART_END_MB}MiB" set 1 esp on

    LOOP=$(losetup -f --show -P "$EFI_IMG")
    cleanup() { losetup -d "$LOOP" 2>/dev/null || true; umount /tmp/uki-esp 2>/dev/null || true; rmdir /tmp/uki-esp 2>/dev/null || true; }
    trap cleanup EXIT

    mkfs.vfat -F 32 -n "EFI" "${LOOP}p1" >/dev/null
    mkdir -p /tmp/uki-esp
    mount "${LOOP}p1" /tmp/uki-esp
    mkdir -p /tmp/uki-esp/EFI/BOOT
    cp "$OUTPUT" /tmp/uki-esp/EFI/BOOT/BOOTX64.EFI
    umount /tmp/uki-esp
    rmdir /tmp/uki-esp
    losetup -d "$LOOP"
    trap - EXIT
    # Allow non-root to use the image with qemu (needs write for OVMF NVRAM)
    chmod a+rw "$EFI_IMG"
fi

# OVMF_VARS must be writable (NVRAM); copy the template each run
cp "$OVMF_VARS_TEMPLATE" "$OVMF_VARS"

echo "Booting $OUTPUT ..."
exec qemu-system-x86_64 \
    -machine q35 \
    -enable-kvm \
    -m 4G \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,file="$OVMF_VARS" \
    -drive format=raw,file="$EFI_IMG" \
    -serial stdio \
    -display none \
    -no-reboot
