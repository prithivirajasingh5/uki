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

for cmd in qemu-system-x86_64 mkfs.vfat mmd mcopy; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "error: $cmd not found — install qemu-system-x86 and mtools" >&2
        exit 1
    fi
done

# Rebuild the FAT image only when rescue.efi is newer than the last image
if [ ! -f "$EFI_IMG" ] || [ "$OUTPUT" -nt "$EFI_IMG" ]; then
    echo "Building EFI boot image..."
    dd if=/dev/zero of="$EFI_IMG" bs=1M count=64 status=none
    mkfs.vfat -q "$EFI_IMG"
    mmd -i "$EFI_IMG" ::/EFI ::/EFI/BOOT
    mcopy -i "$EFI_IMG" "$OUTPUT" ::/EFI/BOOT/BOOTX64.EFI
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
