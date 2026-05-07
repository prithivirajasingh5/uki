# rescue-efi

A single EFI file that boots a complete Debian rescue environment entirely from RAM.
Install it to your EFI partition once and it appears in your firmware boot menu alongside
your existing OS — no USB drive needed at rescue time.

**Pick your path:**
- [I'm on Linux — 4 steps](#install-on-linux)
- [I'm on Windows — 6 steps](#install-on-windows)
- [I'm on a Mac](#not-supported-on-mac) — read this first

> **Mac users:** This project does not support Macs.
> - **Apple Silicon (M1/M2/M3/M4):** the binary is x86_64 — it will not run on ARM, and
>   Apple Silicon does not use standard UEFI.
> - **Intel Mac:** Apple's EFI is non-standard. `efibootmgr` and `mokutil` do not work,
>   WiFi drivers are missing, and T2 Macs require Apple Recovery to change boot security.
>
> There is no supported path for Macs. If you need a Mac rescue environment, use
> [macOS Recovery](https://support.apple.com/en-us/102529) or a macOS-compatible Linux
> live USB.

---

## Which variant?

| | `rescue-mini.efi` | `rescue-full.efi` |
|---|---|---|
| EFI size | ~150 MB | ~700 MB |
| RAM needed | ~500 MB | ~2 GB |
| Disk / partition / format | ✓ | ✓ |
| EFI boot repair (efibootmgr, grub) | ✓ | ✓ |
| btrfs, ext4, FAT filesystems | ✓ | ✓ |
| File editor (nano) | ✓ | ✓ |
| Chroot into installed system | ✓ | ✓ |
| LVM / LUKS | — | ✓ |
| Data recovery (ddrescue, testdisk) | — | ✓ |
| WiFi (iwd) | — | ✓ |
| SSH / rsync | — | ✓ |
| Network tools | — | ✓ |
| Hardware info (lshw, dmidecode) | — | ✓ |

**Start with mini.** It fits on almost any EFI partition and covers the most common rescue
tasks: disk partitioning, filesystem repair, EFI boot repair, chroot.

**Upgrade to full** only if you specifically need WiFi, SSH, LVM, LUKS, or data recovery.

> **EFI partition reality check:** Most OEM Windows laptops ship with a 100–260 MB EFI
> partition. `rescue-full.efi` at ~700 MB won't fit. Even Linux installers typically
> create 512 MB ESPs, which is still tight. **mini is the right choice for on-disk
> installation.**

---

## Install on Linux

**4 steps. ~5 minutes.**

### Step 1 of 4 — Download

```bash
mkdir -p ~/rescue-efi

# mini (~150 MB) — recommended for on-disk install
wget -O ~/rescue-efi/rescue-mini.efi \
    https://github.com/prithivirajasingh5/uki/releases/latest/download/rescue-mini.efi

# full (~700 MB) — only if you need WiFi, SSH, LVM, data recovery
wget -O ~/rescue-efi/rescue-full.efi \
    https://github.com/prithivirajasingh5/uki/releases/latest/download/rescue-full.efi
```

Or grab both from the [releases page](https://github.com/prithivirajasingh5/uki/releases/latest).

### Step 2 of 4 — Sign for Secure Boot

Check whether Secure Boot is active:

```bash
mokutil --sb-state
```

**If `SecureBoot disabled`:** skip to Step 3.

**If `SecureBoot enabled`:**

```bash
# Install signing tools (one-time)
sudo apt install sbsigntool openssl mokutil

# Generate a key pair (one-time — keep rescue.key safe, never share it)
mkdir -p ~/rescue-keys
openssl req -newkey rsa:2048 -nodes -keyout ~/rescue-keys/rescue.key \
    -new -x509 -sha256 -days 3650 \
    -subj "/CN=Rescue EFI Signing Key/" \
    -out ~/rescue-keys/rescue.crt
openssl x509 -in ~/rescue-keys/rescue.crt -outform DER -out ~/rescue-keys/rescue.cer

# Sign (replace rescue-mini with rescue-full if using full)
sbsign --key ~/rescue-keys/rescue.key --cert ~/rescue-keys/rescue.crt \
       --output ~/rescue-efi/rescue-mini.efi ~/rescue-efi/rescue-mini.efi

# Verify the signature
sbverify --cert ~/rescue-keys/rescue.crt ~/rescue-efi/rescue-mini.efi && echo "OK"

# Enroll your key — set a short one-time password when prompted
sudo mokutil --import ~/rescue-keys/rescue.cer
```

Reboot. **MokManager** will appear — enter the password you set, select **Enroll MOK**,
and reboot again. Your key is now trusted by the firmware. Continue to Step 3.

### Step 3 of 4 — Install on the EFI partition

Check free space on your EFI partition (~150 MB needed for mini, ~700 MB for full):

```bash
df -h /boot/efi
```

Find your EFI disk and partition number:

```bash
findmnt -n -o SOURCE /boot/efi
# e.g.  /dev/sda1      → disk=/dev/sda,     part=1
#        /dev/nvme0n1p1 → disk=/dev/nvme0n1, part=1
```

Copy the file and register the boot entry:

```bash
sudo mkdir -p /boot/efi/EFI/rescue

# Use rescue-full.efi here if you downloaded full
sudo cp ~/rescue-efi/rescue-mini.efi /boot/efi/EFI/rescue/rescue.efi

# Replace /dev/sda and 1 with your disk and partition number from above
sudo efibootmgr --create --disk /dev/sda --part 1 \
    --label "Rescue EFI" --loader '\EFI\rescue\rescue.efi'
```

### Step 4 of 4 — Verify and reboot

```bash
efibootmgr -v | grep -i rescue
# Boot0003* Rescue EFI  HD(1,GPT,...)/File(\EFI\rescue\rescue.efi)
```

Reboot and select **Rescue EFI** from the firmware boot menu (usually F12 or F2 at POST).
Type `readme` at the rescue shell for a quick reference card.

**Updating rescue.efi later** (re-sign first if Secure Boot is enabled, then copy — the
NVRAM boot entry persists):

```bash
sbsign --key ~/rescue-keys/rescue.key --cert ~/rescue-keys/rescue.crt \
       --output ~/rescue-efi/rescue-mini.efi ~/rescue-efi/rescue-mini.efi
sudo cp ~/rescue-efi/rescue-mini.efi /boot/efi/EFI/rescue/rescue.efi
```

---

## Install on Windows

**6 steps. Requires a Linux live USB (Ubuntu, Fedora, etc.) to complete.**

The signing tools and EFI management commands (`sbsign`, `efibootmgr`, `mokutil`) require
native Linux. WSL2 can sign the binary but cannot write to EFI NVRAM, so `efibootmgr`
and `mokutil` won't work from it.

### Step 1 of 6 — Back up your BitLocker recovery key

**Do this before touching anything in firmware settings.** Changing Secure Boot state
shifts the TPM measurements BitLocker depends on — Windows may demand your 48-digit
recovery key on the very next boot. If you don't have it, you're locked out of your drive.

Back it up at: **account.microsoft.com/devices/recoverykey**

Or from an admin PowerShell:

```powershell
manage-bde -protectors -get C:
```

Save it somewhere other than this laptop — phone, paper, another machine.

### Step 2 of 6 — Check Secure Boot state and EFI partition size

**Secure Boot state:**

```
msinfo32
```

Look for **Secure Boot State** under System Summary. Note whether it's On or Off.

**EFI partition size:**

```powershell
# Admin PowerShell
Get-Partition | Where-Object IsSystem | Select-Object DiskNumber, PartitionNumber, @{n='SizeMB';e={[math]::Round($_.Size/1MB)}}
```

Or from an admin Command Prompt:

```
diskpart
list disk
select disk 0
list partition
exit
```

Look for the **System** type partition. rescue-mini (~150 MB) fits on most OEM ESPs.
rescue-full (~700 MB) almost certainly does not — use mini for on-disk install.

### Step 3 of 6 — Download rescue-mini.efi on Windows

Download from the [releases page](https://github.com/prithivirajasingh5/uki/releases/latest)
and save it somewhere you can access from the Linux live environment — a FAT32 USB stick
works well, or you can re-download it in Step 5 using `curl`.

### Step 4 of 6 — Suspend BitLocker and disable Secure Boot

Suspend BitLocker first so Windows doesn't demand your recovery key after the firmware
change:

```powershell
# Admin PowerShell — suspends protection for one reboot only
Suspend-BitLocker -MountPoint C: -RebootCount 1
```

Reboot into firmware settings. Fastest path on Windows 10/11:

**Settings → System → Recovery → Advanced startup → Restart now →
Troubleshoot → Advanced options → UEFI Firmware Settings → Restart**

(Or press F2 / Del / F10 / Esc at POST — varies by OEM.)

Find **Secure Boot** and set it to **Disabled**. Save and exit.

### Step 5 of 6 — Sign and install from the Linux live USB

Boot your Linux live USB. Then:

```bash
# Install tools
sudo apt install sbsigntool openssl mokutil efibootmgr

# Find your Windows EFI partition (look for ~100-512 MB vfat partition)
lsblk -f

# Mount it
sudo mkdir /mnt/efi
sudo mount /dev/nvme0n1p1 /mnt/efi   # adjust device to match lsblk output

# Get rescue-mini.efi (or copy from FAT32 USB if you prepared one in Step 3)
curl -LO https://github.com/prithivirajasingh5/uki/releases/latest/download/rescue-mini.efi

# Generate a signing key
mkdir -p ~/rescue-keys
openssl req -newkey rsa:2048 -nodes -keyout ~/rescue-keys/rescue.key \
    -new -x509 -sha256 -days 3650 \
    -subj "/CN=Rescue EFI Signing Key/" \
    -out ~/rescue-keys/rescue.crt
openssl x509 -in ~/rescue-keys/rescue.crt -outform DER -out ~/rescue-keys/rescue.cer

# Copy and sign
sudo mkdir -p /mnt/efi/EFI/rescue
sudo cp rescue-mini.efi /mnt/efi/EFI/rescue/rescue.efi
sudo sbsign --key ~/rescue-keys/rescue.key --cert ~/rescue-keys/rescue.crt \
       --output /mnt/efi/EFI/rescue/rescue.efi /mnt/efi/EFI/rescue/rescue.efi

# Register the boot entry (adjust disk and part number to match your device)
sudo efibootmgr --create --disk /dev/nvme0n1 --part 1 \
    --label "Rescue EFI" --loader '\EFI\rescue\rescue.efi'

# Enroll your signing key — set a short one-time password when prompted
sudo mokutil --import ~/rescue-keys/rescue.cer
```

> **Save your signing key before rebooting** — it lives in RAM and will be gone.
> Copy to your FAT32 USB stick or note it down:
> ```bash
> cp ~/rescue-keys/rescue.key /path/to/usb/
> cp ~/rescue-keys/rescue.crt /path/to/usb/
> ```

### Step 6 of 6 — Enroll the key and re-enable Secure Boot

Reboot. **MokManager** will appear (blue screen). Enter the password you set in Step 5,
select **Enroll MOK → Continue → Yes → Reboot**.

Once back in Windows: re-enter firmware settings and re-enable Secure Boot. rescue.efi
is now signed with a key your firmware trusts and will boot normally.

**Updating rescue.efi later** — from your Linux live USB (or any Linux machine with the
saved key):

```bash
sbsign --key rescue.key --cert rescue.crt \
       --output rescue-mini.efi rescue-mini.efi
# then mount EFI partition and copy as in Step 5
```

### Risk summary

| Action | Risk | How to avoid it |
|---|---|---|
| Change Secure Boot in firmware | BitLocker demands recovery key on next boot | Back up key first; suspend BitLocker before entering firmware |
| Enroll a MOK key | BitLocker may trigger on reboot | Same — suspend BitLocker before rebooting into MokManager |
| Copy files to EFI partition | Overwrite Windows bootloader | Only write to `EFI\rescue\` — never touch `EFI\Microsoft\` |
| Lose `rescue.key` | Can't sign updated rescue.efi | Copy key off the live USB session before rebooting |
| Skip BitLocker backup | Permanent data loss if key is unknown | 30 seconds at account.microsoft.com/devices/recoverykey |

---

## Reference

### What's inside

*Full variant. Mini includes the disk / EFI repair subset — see the variant table above.*

| Category | Tools | mini |
|---|---|:---:|
| Partitioning | `parted`, `gdisk` | ✓ |
| Filesystems | `btrfs-progs`, `e2fsprogs`, `dosfstools`, `xfsprogs`, `ntfs-3g`, `exfatprogs` | ✓ |
| Encryption / LVM | `cryptsetup`, `lvm2` | — |
| NVMe | `nvme-cli` | ✓ |
| Disk health | `smartmontools`, `testdisk`, `ddrescue` | — |
| EFI boot repair | `efibootmgr`, `grub-efi-amd64-bin` | ✓ |
| WiFi | `iwd` + `iproute2` (no wpa_supplicant needed) | — |
| Networking | `dhclient`, `ping`, `traceroute`, `nc`, `tcpdump`, `ethtool`, `dig` | — |
| Remote access | `openssh-client`, `rsync` | — |
| Hardware info | `lshw`, `dmidecode`, `pciutils`, `usbutils` | `pciutils` only |
| Editors | `nano`, `vim-tiny` | ✓ |
| Utilities | `curl`, `less`, `file`, `find`, `tree`, `htop`, `lsof`, `strace` | `less`, `find`, `tree` only |

Type `readme` at the rescue shell for a quick reference card.

### Build from source

Instead of downloading a pre-built binary, you can build locally on Debian/Ubuntu x86_64:

```bash
curl -fsSL https://raw.githubusercontent.com/prithivirajasingh5/uki/master/install.sh | bash
```

The script clones this repo, installs build dependencies, and runs `sudo make all`.
Output: `~/rescue-efi/rescue-mini.efi` and `~/rescue-efi/rescue-full.efi`

Or manually:

```bash
git clone https://github.com/prithivirajasingh5/uki.git
cd uki
sudo make all     # builds both rescue-mini.efi and rescue-full.efi
sudo make mini    # builds rescue-mini.efi only
sudo make full    # builds rescue-full.efi only
```

Intermediate steps for finer control:

```bash
sudo make deps                   # check and install host build dependencies
sudo make rootfs VARIANT=mini    # debootstrap Debian into work/mini/rootfs/  (~5 min)
sudo make squashfs VARIANT=mini  # compress to work/mini/root.squashfs         (~30 s)
sudo make initramfs VARIANT=mini
sudo make uki VARIANT=mini       # ukify → rescue-mini.efi
```

Each step is incremental — make only reruns a step if its inputs are newer than its output.

**Targeting a specific kernel:**

```bash
sudo make mini KERNEL=/boot/vmlinuz-6.8.0-51-generic
sudo make full KERNEL=/boot/vmlinuz-6.8.0-51-generic
```

**Rebuilding after changes:**

```bash
sudo make all                       # rebuild both variants
sudo make uki VARIANT=mini          # rebuild only the EFI (rootfs/squashfs unchanged)
sudo make clean && sudo make all    # full clean rebuild of both variants
```

### Requirements

- Build host: Debian or Ubuntu, x86_64
- Build disk space: ~500 MB for mini, ~2 GB for full
- Rescue target: UEFI firmware (BIOS/MBR not supported)
- Rescue target RAM: ~500 MB for mini, ~2 GB for full

Build-time packages installed automatically by `make deps`:
`debootstrap`, `squashfs-tools`, `systemd-ukify`, `busybox-static`

### How it works

```
rescue.efi  (PE/EFI binary — one file)
  ├── .linux   → kernel image (from build host)
  ├── .initrd  → cpio.gz containing:
  │    ├── /init          POSIX sh script (PID 1)
  │    ├── busybox        static binary: sh, mount, switch_root …
  │    ├── unsquashfs     extracts the rootfs
  │    └── root.squashfs  compressed Debian rootfs
  └── .cmdline → console=ttyS0,115200 console=tty0
```

On boot:
1. UEFI loads `rescue.efi` and hands off to the kernel
2. The kernel runs `/init` (our script, PID 1)
3. `init` mounts a tmpfs at `/newroot`, extracts `root.squashfs` into it, then calls `switch_root`
4. systemd starts in the fully writable Debian environment

See [`docs/design.md`](docs/design.md) for the full design rationale.

### WiFi (full variant only)

```bash
iwctl
  station wlan0 scan
  station wlan0 get-networks
  station wlan0 connect "MyNetwork"
  quit

ip addr show wlan0   # verify IP (iwd handles DHCP automatically)
```

See [`docs/wifi-setup.md`](docs/wifi-setup.md) for hidden networks, static IP, and SSH.

---

## License

MIT
