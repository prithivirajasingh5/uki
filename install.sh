#!/bin/bash
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/prithivirajasingh5/uki/master/install.sh | bash
#   bash install.sh
set -euo pipefail

REPO="https://github.com/prithivirajasingh5/uki.git"
RESCUE_DIR="${RESCUE_DIR:-$HOME/rescue-efi}"
VARIANT="${VARIANT:-full}"

print_banner() {
    echo ""
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║         rescue-efi  builder              ║"
    echo "  ║  single EFI binary · boots from RAM      ║"
    echo "  ╚══════════════════════════════════════════╝"
    echo ""
}

die() { echo "error: $*" >&2; exit 1; }

# ── OS check ────────────────────────────────────────────────────────────────
check_os() {
    if [ "$(uname -m)" != "x86_64" ]; then
        die "only x86_64 is supported (got $(uname -m))"
    fi
    if ! command -v apt-get >/dev/null 2>&1; then
        die "this installer requires a Debian/Ubuntu system with apt-get"
    fi
}

# ── install git if missing ───────────────────────────────────────────────────
ensure_git() {
    if ! command -v git >/dev/null 2>&1; then
        echo "==> git not found — installing..."
        sudo apt-get update -qq
        sudo apt-get install -y git
    fi
}

# ── clone or update repo ─────────────────────────────────────────────────────
fetch_repo() {
    if [ -d "$RESCUE_DIR/.git" ]; then
        echo "==> Found existing clone at $RESCUE_DIR — pulling latest..."
        git -C "$RESCUE_DIR" pull --ff-only
    else
        echo "==> Cloning rescue-efi into $RESCUE_DIR ..."
        git clone "$REPO" "$RESCUE_DIR"
    fi
}

# ── build ────────────────────────────────────────────────────────────────────
build() {
    echo ""
    echo "==> Building rescue-$VARIANT.efi (this takes ~15 minutes on first run for full, ~5 min for mini)."
    echo "    Root access is required for debootstrap and kernel module copy."
    echo ""
    sudo make -C "$RESCUE_DIR" VARIANT="$VARIANT" all
}

# ── done ─────────────────────────────────────────────────────────────────────
print_done() {
    local efi="$RESCUE_DIR/rescue-$VARIANT.efi"
    local size
    size=$(du -sh "$efi" 2>/dev/null | cut -f1 || echo "?")
    echo ""
    echo "  ✓ Done!  rescue.efi ($size) is at:"
    echo "    $efi"
    echo ""
    echo "  To put it on a USB stick:"
    echo "    1. Format a USB with a FAT32 EFI partition (or reuse an existing ESP)"
    echo "    2. Copy:  cp $efi /path/to/usb/EFI/BOOT/BOOTX64.EFI"
    echo "    3. Boot the USB from your UEFI firmware menu"
    echo ""
    echo "  To rebuild after changes:"
    echo "    sudo make -C $RESCUE_DIR all"
    echo ""
}

# ── main ─────────────────────────────────────────────────────────────────────
print_banner
check_os
ensure_git
fetch_repo
build
print_done
