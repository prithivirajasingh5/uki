#!/bin/bash
set -euo pipefail

SCRIPTS=(src/build-rootfs.sh src/build-squashfs.sh src/build-initramfs.sh src/build-uki.sh)
INIT=src/initramfs/init

echo "Running shellcheck..."

# Bash scripts — check with bash dialect
shellcheck --shell=bash "${SCRIPTS[@]}"

# init is POSIX sh — enforce strictly
shellcheck --shell=sh "$INIT"

echo "shellcheck passed"
