#!/bin/bash
set -euo pipefail

ROOTFS="${ROOTFS:-work/full/rootfs}"
SQUASHFS="${SQUASHFS:-work/full/root.squashfs}"

if [ ! -f "$ROOTFS/.done" ]; then
    echo "error: rootfs not built — run 'make rootfs' first" >&2
    exit 1
fi

echo "Compressing $ROOTFS -> $SQUASHFS ..."
mksquashfs "$ROOTFS" "$SQUASHFS" \
    -comp zstd \
    -Xcompression-level 15 \
    -noappend \
    -no-progress \
    -wildcards \
    -e "var/cache/apt/*" \
    -e "var/lib/apt/lists/*"

echo "Done: $SQUASHFS ($(du -sh "$SQUASHFS" | cut -f1))"
