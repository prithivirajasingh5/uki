#!/bin/bash
set -euo pipefail

INITRAMFS=work/initramfs.cpio.gz
OUTPUT=rescue.efi
CMDLINE="console=ttyS0,115200 console=tty0 quiet"

if [ -z "${KERNEL:-}" ]; then
    KERNEL=$(find /boot -maxdepth 1 -name 'vmlinuz-*' 2>/dev/null | sort -V | tail -1)
fi

if [ -z "$KERNEL" ] || [ ! -f "$KERNEL" ]; then
    echo "error: kernel not found — set KERNEL=/boot/vmlinuz-<version>" >&2
    exit 1
fi

if [ ! -f "$INITRAMFS" ]; then
    echo "error: $INITRAMFS not found — run 'make initramfs' first" >&2
    exit 1
fi

# Ubuntu sets /boot/vmlinuz-* to root:root 600; copy to a readable temp file
BOOT_KERNEL="$KERNEL"
if [ ! -r "$KERNEL" ]; then
    BOOT_KERNEL=$(mktemp /tmp/vmlinuz.XXXXXX)
    sudo cp "$KERNEL" "$BOOT_KERNEL"
    sudo chmod 644 "$BOOT_KERNEL"
    trap 'rm -f "$BOOT_KERNEL"' EXIT
fi

echo "Building UKI: kernel=$KERNEL"
ukify build \
    --linux "$BOOT_KERNEL" \
    --initrd "$INITRAMFS" \
    --cmdline "$CMDLINE" \
    --output "$OUTPUT"

echo "Done: $OUTPUT ($(du -sh "$OUTPUT" | cut -f1))"
