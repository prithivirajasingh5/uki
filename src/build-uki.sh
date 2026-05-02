#!/bin/bash
set -euo pipefail

INITRAMFS=work/initramfs.cpio.gz
OUTPUT=rescue.efi
CMDLINE="console=ttyS0 console=tty0 quiet"

if [ -z "${KERNEL:-}" ]; then
    KERNEL=$(ls /boot/vmlinuz-* 2>/dev/null | sort -V | tail -1)
fi

if [ -z "$KERNEL" ] || [ ! -f "$KERNEL" ]; then
    echo "error: kernel not found — set KERNEL=/boot/vmlinuz-<version>" >&2
    exit 1
fi

if [ ! -f "$INITRAMFS" ]; then
    echo "error: $INITRAMFS not found — run 'make initramfs' first" >&2
    exit 1
fi

echo "Building UKI: kernel=$KERNEL"
ukify build \
    --linux "$KERNEL" \
    --initrd "$INITRAMFS" \
    --cmdline "$CMDLINE" \
    --output "$OUTPUT"

echo "Done: $OUTPUT ($(du -sh "$OUTPUT" | cut -f1))"
