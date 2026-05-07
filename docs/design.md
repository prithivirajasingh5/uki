# Design Notes

## What this is

A single self-contained EFI binary (`rescue.efi`) that boots a full Debian rescue
environment entirely from RAM. Drop it on any UEFI machine — no installer, no disk,
no network required at boot time.

## Boot flow

```
UEFI firmware
  └─ loads rescue.efi          (PE/EFI binary — the UKI)
       ├─ .linux  → vmlinuz    kernel image
       ├─ .initrd → initramfs  cpio.gz containing:
       │    ├─ /init            our POSIX sh script (PID 1)
       │    ├─ busybox          provides sh, mount, switch_root, etc.
       │    ├─ unsquashfs       extracts the rootfs
       │    └─ root.squashfs   compressed Debian rootfs
       └─ .cmdline              console=ttyS0,115200 console=tty0 quiet

kernel starts
  └─ runs /init (our script)
       1. mount proc, sysfs, devtmpfs
       2. mount tmpfs at /newroot  (100% of RAM ceiling)
       3. unsquashfs root.squashfs → /newroot
       4. exec switch_root /newroot /sbin/init

systemd starts in /newroot
  └─ rescue environment is live
```

## Why a UKI

A Unified Kernel Image packs kernel + initramfs + cmdline into one PE binary.
This gives us:

- **One file to manage** — copy `rescue.efi` to a USB stick's ESP and it just works.
- **Secure Boot friendly** — one signature covers everything; no separate signed
  initramfs or cmdline to manage.
- **Immutable cmdline** — the console and boot options are baked in, not editable
  from a boot menu.

## Why squashfs-in-initramfs

The rootfs is stored as a squashfs image *inside* the initramfs rather than on a
separate partition. This means:

- No disk partitioning required on the rescue target
- The entire system fits in one EFI file
- zstd compression keeps the image small (~66 MB for a full Debian environment)

The trade-off: the full rootfs is extracted into tmpfs on every boot. On a machine
with 4 GB RAM this uses ~180 MB. On machines with less than ~2 GB RAM this may
be tight, especially once kernel modules and firmware blobs are included.

## Why tmpfs (not a squashfs loop mount)

Extracting to tmpfs makes the running system fully writable — you can install
packages, edit configs, and persist changes within a session. A read-only squashfs
loop mount would require an overlay (like overlayfs) for any writes, adding
complexity for a rescue tool that rarely needs persistence.

## Build pipeline

```
make rootfs      debootstrap → work/rootfs/         (~10 min, needs root)
make squashfs    mksquashfs  → work/root.squashfs   (~30 s)
make initramfs   cpio        → work/initramfs.cpio.gz (~5 s)
make uki         ukify       → rescue.efi            (~5 s)
```

Each step is idempotent. Make only reruns a step if its output is older than
its input. The rootfs step is guarded by a `.done` sentinel to avoid re-running
the slow debootstrap.

## Packages baked in

| Package | Purpose |
|---|---|
**Both variants (mini + full):**

| Package | Purpose |
|---|---|
| `parted`, `gdisk` | Partition disks |
| `btrfs-progs` | Create/repair btrfs filesystems |
| `nvme-cli` | Inspect and manage NVMe drives |
| `pciutils` | `lspci` — PCI device identification |
| `lshw` | Full hardware inventory |
| `squashfs-tools` | `unsquashfs` available inside the running rescue system |
| `bash`, `util-linux` | Standard shell and disk utilities |

**Full variant only:**

| Package | Purpose |
|---|---|
| `usbutils` | `lsusb` — USB device identification |
| `iwd` + `iproute2` | WiFi without a daemon (see `docs/wifi-setup.md`) |
| `openssh-client` | SSH to router or remote hosts |
| `curl` | Fetch files over HTTP/HTTPS |
| `smartmontools`, `testdisk`, `gddrescue` | Disk health and data recovery |
| `lvm2`, `cryptsetup` | LVM and LUKS encrypted volumes |

## Bell / beep suppression

The terminal bell is silenced by default in both variants via three mechanisms
applied at rootfs build time:

- `blacklist pcspkr` in `/etc/modprobe.d/nobeep.conf` — prevents the PC speaker
  kernel module from loading, so no hardware beep can fire at all
- `set bell-style none` in `/etc/inputrc` — tells readline (bash, python REPL,
  etc.) to never emit the BEL character for tab-complete or end-of-history events
- `LESS="-q"` in `/etc/profile.d/nobell.sh` — stops the `less` pager from beeping
  when you scroll past the end of a file

## Kernel

The kernel is taken from the build host (`/boot/vmlinuz-*`, latest version). This
means `rescue.efi` uses whatever kernel the build machine has, including its module
set. No out-of-tree modules are available at runtime (modules are not included in
the image).

To target a specific kernel version: `make uki KERNEL=/boot/vmlinuz-<version>`
