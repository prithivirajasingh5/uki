#!/bin/bash
set -euo pipefail

OUTPUT=rescue.efi
EFI_IMG=work/efi.img

# Locate OVMF firmware
OVMF=$(find /usr/share -name "OVMF.fd" 2>/dev/null | head -1)

if [ ! -f "$OUTPUT" ]; then
    echo "error: $OUTPUT not found — run 'make uki' first" >&2
    exit 1
fi

if [ -z "$OVMF" ]; then
    echo "error: OVMF.fd not found — install ovmf package" >&2
    exit 1
fi

for cmd in qemu-system-x86_64 parted mformat mmd mcopy; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "error: $cmd not found — install qemu-system-x86 and mtools" >&2
        exit 1
    fi
done

# Rebuild the disk image only when rescue.efi is newer than the last image.
# OVMF requires a real GPT disk with an EFI System Partition — a bare FAT
# image is not detected as bootable. mtools' @@offset syntax lets us format
# and populate the partition directly without a loop device or root.
if [ ! -f "$EFI_IMG" ] || [ "$OUTPUT" -nt "$EFI_IMG" ]; then
    echo "Building EFI boot image..."
    dd if=/dev/zero of="$EFI_IMG" bs=1M count=64 status=none
    parted -s "$EFI_IMG" mklabel gpt mkpart ESP fat32 1MiB 63MiB set 1 esp on
    # ESP starts at 1 MiB (1048576 bytes); use mtools offset syntax @@<bytes>
    mformat -i "$EFI_IMG@@1048576" -F -v "EFI"
    mmd    -i "$EFI_IMG@@1048576" ::/EFI ::/EFI/BOOT
    mcopy  -i "$EFI_IMG@@1048576" "$OUTPUT" ::/EFI/BOOT/BOOTX64.EFI
fi

echo "Booting $OUTPUT (OVMF: $OVMF) ..."
qemu-system-x86_64 \
    -enable-kvm \
    -m 2G \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF" \
    -drive format=raw,file="$EFI_IMG" \
    -serial stdio \
    -display none \
    -no-reboot
