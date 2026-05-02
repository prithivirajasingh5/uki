#!/bin/bash
set -euo pipefail

KERNEL=${KERNEL:-$(find /boot -maxdepth 1 -name 'vmlinuz-*' 2>/dev/null | sort -V | tail -1)}
INITRAMFS=work/initramfs.cpio.gz
LOG=/tmp/uki-smoke.log
TIMEOUT=90

if [ ! -f "$INITRAMFS" ]; then
    echo "error: $INITRAMFS not found — run 'make initramfs' first" >&2
    exit 1
fi

if [ -z "$KERNEL" ] || [ ! -f "$KERNEL" ]; then
    echo "error: kernel not found — set KERNEL=/boot/vmlinuz-<version>" >&2
    exit 1
fi

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "error: qemu-system-x86_64 not found — install qemu-system-x86" >&2
    exit 1
fi

# Ubuntu restricts /boot/vmlinuz-* to root:root 600; copy to a readable temp file
BOOT_KERNEL="$KERNEL"
if [ ! -r "$KERNEL" ]; then
    BOOT_KERNEL=$(mktemp /tmp/vmlinuz.XXXXXX)
    sudo cp "$KERNEL" "$BOOT_KERNEL"
    sudo chmod 644 "$BOOT_KERNEL"
    trap 'rm -f "$BOOT_KERNEL"' EXIT
fi

echo "Booting kernel=$KERNEL initramfs=$INITRAMFS ..."
echo "(timeout ${TIMEOUT}s, log: $LOG)"

timeout "$TIMEOUT" qemu-system-x86_64 \
    -enable-kvm \
    -m 2G \
    -kernel "$BOOT_KERNEL" \
    -initrd "$INITRAMFS" \
    -append "console=ttyS0 quiet" \
    -serial stdio \
    -display none \
    -no-reboot 2>&1 | tee "$LOG" || true

if grep -q "switch_root" "$LOG"; then
    echo "PASS: switch_root reached"
else
    echo "FAIL: switch_root not seen in output (check $LOG)"
    exit 1
fi
