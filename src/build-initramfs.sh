#!/bin/bash
set -euo pipefail

SQUASHFS="${SQUASHFS:-work/full/root.squashfs}"
IDIR="${IDIR:-work/full/initramfs-stage}"
INITRAMFS="${INITRAMFS:-work/full/initramfs.cpio.gz}"

if [ ! -f "$SQUASHFS" ]; then
    echo "error: $SQUASHFS not found — run 'make squashfs' first" >&2
    exit 1
fi

# Copy a binary and all its dynamic libraries into $IDIR
copy_with_libs() {
    local bin="$1"
    local dest
    dest="$IDIR/bin/$(basename "$bin")"
    cp "$bin" "$dest"
    chmod +x "$dest"
    # Extract every absolute path from ldd output (handles both "=> /path" and
    # the bare interpreter line "/lib64/ld-linux-x86-64.so.2")
    ldd "$bin" 2>/dev/null | grep -oE '/[^ ]+' | while read -r lib; do
        [ -f "$lib" ] || continue
        local libdest="$IDIR$lib"
        mkdir -p "$(dirname "$libdest")"
        cp -L "$lib" "$libdest"
    done
}

rm -rf "$IDIR"
mkdir -p "$IDIR"/{bin,sbin,dev,etc,lib,lib64,proc,sys,newroot,run}

# Pre-create essential device nodes so the kernel can open /dev/console for
# PID 1 stdio before devtmpfs is mounted; without these the kernel falls back
# to /dev/null and all init output is silently discarded.
mknod -m 0600 "$IDIR/dev/console" c 5 1
mknod -m 0666 "$IDIR/dev/null"    c 1 3
mknod -m 0660 "$IDIR/dev/tty"     c 5 0

# busybox provides: sh, mount, umount, mkdir, mknod, switch_root, echo
BUSYBOX=$(command -v busybox || true)
if [ -z "$BUSYBOX" ]; then
    echo "error: busybox not found — install busybox-static" >&2
    exit 1
fi
cp "$BUSYBOX" "$IDIR/bin/busybox"
chmod +x "$IDIR/bin/busybox"

for cmd in sh mount umount mkdir mknod switch_root echo; do
    ln -sf busybox "$IDIR/bin/$cmd"
done

# unsquashfs — needed to extract the rootfs (dynamically linked, copy with libs)
UNSQUASHFS=$(command -v unsquashfs || true)
if [ -z "$UNSQUASHFS" ]; then
    echo "error: unsquashfs not found — install squashfs-tools" >&2
    exit 1
fi
copy_with_libs "$UNSQUASHFS"

# init script
install -m 0755 src/initramfs/init "$IDIR/init"

# squashfs image
cp "$SQUASHFS" "$IDIR/root.squashfs"

# pack into cpio.gz
echo "Packing initramfs..."
(cd "$IDIR" && find . | cpio -oH newc) | gzip -9 > "$INITRAMFS"

echo "Done: $INITRAMFS ($(du -sh "$INITRAMFS" | cut -f1))"
