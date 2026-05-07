# rescue-efi

A single self-contained EFI binary that boots a full Debian rescue environment entirely from RAM.

Drop `rescue.efi` onto any UEFI machine — no installer, no USB formatting tool, no network
required at boot time. The kernel, rootfs, and all tools are packed into one file.

---

## Get rescue.efi

Two variants are available:

| | `rescue-full.efi` | `rescue-mini.efi` |
|---|---|---|
| EFI size | ~700 MB | ~150 MB |
| RAM needed | ~2 GB | ~500 MB |
| Disk / partition / format | ✓ | ✓ |
| EFI boot repair (efibootmgr, grub) | ✓ | ✓ |
| File editor (nano) | ✓ | ✓ |
| Chroot into installed system | ✓ | ✓ |
| LVM / LUKS | ✓ | — |
| Data recovery (ddrescue, testdisk) | ✓ | — |
| WiFi (iwd) | ✓ | — |
| SSH / rsync | ✓ | — |
| Network tools | ✓ | — |
| Hardware info (lshw, dmidecode) | ✓ | — |

**Choose mini** if you just need to partition disks, fix grub, or edit a config file.
**Choose full** if you need WiFi, SSH, data recovery, LVM, or LUKS.

> **EFI partition reality check:** Most OEM laptops shipped with Windows have a 100–260 MB EFI
> partition — `rescue-full.efi` at ~700 MB won't fit. Even Linux installers typically create
> 512 MB ESPs, which is still tight. **Use mini for on-disk installation; put full on a USB drive.**

**Option A — Download pre-built** (fastest):

```bash
mkdir -p ~/rescue-efi

# full (~700 MB)
wget -O ~/rescue-efi/rescue-full.efi \
    https://github.com/prithivirajasingh5/uki/releases/latest/download/rescue-full.efi

# mini (~150 MB)
wget -O ~/rescue-efi/rescue-mini.efi \
    https://github.com/prithivirajasingh5/uki/releases/latest/download/rescue-mini.efi
```

Or grab them from the [releases page](https://github.com/prithivirajasingh5/uki/releases/latest).

**Option B — Build from source** (Debian/Ubuntu x86_64):

```bash
# builds both rescue-full.efi and rescue-mini.efi (~15 min)
curl -fsSL https://raw.githubusercontent.com/prithivirajasingh5/uki/master/install.sh | bash
```

The script clones this repo, installs any missing build dependencies, and runs `sudo make all`.
It will prompt for your sudo password when the build starts.

Output: `~/rescue-efi/rescue-full.efi` and `~/rescue-efi/rescue-mini.efi`

---

## Sign for Secure Boot

Most modern machines have Secure Boot enabled and will refuse to boot an unsigned EFI binary.
Sign your chosen variant before installing. Check whether Secure Boot is active:

```bash
mokutil --sb-state
# "SecureBoot enabled"  → follow all steps below
# "SecureBoot disabled" → skip this section
```

```bash
# Install signing tools (one-time)
sudo apt install sbsigntool openssl mokutil

# Generate a private key and certificate (one-time — keep rescue.key safe, never share it)
mkdir -p ~/rescue-keys
openssl req -newkey rsa:2048 -nodes -keyout ~/rescue-keys/rescue.key \
    -new -x509 -sha256 -days 3650 \
    -subj "/CN=Rescue EFI Signing Key/" \
    -out ~/rescue-keys/rescue.crt
openssl x509 -in ~/rescue-keys/rescue.crt -outform DER -out ~/rescue-keys/rescue.cer

# Sign the image in-place (replace rescue-full.efi with rescue-mini.efi if using mini)
sbsign --key ~/rescue-keys/rescue.key --cert ~/rescue-keys/rescue.crt \
       --output ~/rescue-efi/rescue-full.efi ~/rescue-efi/rescue-full.efi

# Verify
sbverify --cert ~/rescue-keys/rescue.crt ~/rescue-efi/rescue-full.efi && echo "signature OK"

# Enroll your key via MOK — enter a one-time password when prompted
sudo mokutil --import ~/rescue-keys/rescue.cer
```

Now reboot. **MokManager** will appear on the next boot — enter the password you just set,
select **Enroll MOK**, and reboot again. Your key is now trusted by the firmware.

After enrollment, `rescue.efi` will boot with Secure Boot active. See
[`docs/secure-boot-signing.md`](docs/secure-boot-signing.md) for advanced options
(signing at build time, YubiKey, verifying enrollment).

---

## Install on a Linux machine

You can register `rescue.efi` as a permanent boot entry on the same laptop alongside
your existing OS. It will appear in your UEFI firmware boot menu.

### 1. Check EFI partition space

The EFI partition should have at least 1 GB of total capacity and enough free space
for `rescue.efi` (~700 MB). Check both:

```bash
# Total size and free space
df -h /boot/efi

# Partition size on disk
lsblk -o NAME,SIZE,MOUNTPOINT | grep /boot/efi
```

If free space is tight, resizing the EFI partition while the OS is running is risky —
consider a dedicated rescue laptop or a larger EFI partition.

### 2. Find your EFI disk and partition number

`efibootmgr` needs the raw disk device and the partition number separately:

```bash
findmnt -n -o SOURCE /boot/efi
# e.g.  /dev/sda1      → disk=/dev/sda,      part=1
#        /dev/nvme0n1p1 → disk=/dev/nvme0n1,  part=1
#        /dev/nvme0n1p2 → disk=/dev/nvme0n1,  part=2
```

### 3. Create the directory, copy the file, register the boot entry

```bash
sudo mkdir -p /boot/efi/EFI/rescue

# Copy your chosen variant (adjust filename if using mini)
sudo cp ~/rescue-efi/rescue-full.efi /boot/efi/EFI/rescue/rescue.efi

# Replace /dev/sda and 1 with your disk and partition number from step 2
sudo efibootmgr --create --disk /dev/sda --part 1 \
    --label "Rescue EFI" --loader '\EFI\rescue\rescue.efi'
```

### 4. Verify

```bash
efibootmgr -v | grep -i rescue
# Should print something like:
# Boot0003* Rescue EFI  HD(1,GPT,...)/File(\EFI\rescue\rescue.efi)
```

Reboot and select **Rescue EFI** from the firmware boot menu (usually F12 or F2 at POST).

### Updating rescue.efi later

Re-sign first (if Secure Boot is enabled), then copy — the NVRAM entry persists:

```bash
sbsign --key ~/rescue-keys/rescue.key --cert ~/rescue-keys/rescue.crt \
       --output ~/rescue-efi/rescue-full.efi ~/rescue-efi/rescue-full.efi
sudo cp ~/rescue-efi/rescue-full.efi /boot/efi/EFI/rescue/rescue.efi
```

---

## Install on a Windows machine

rescue-efi works on any UEFI machine regardless of OS. The two obstacles for Windows
users are **Secure Boot** and **BitLocker**.

### Step 0 — Back up your BitLocker recovery key (do this first)

**Do this before touching anything in firmware settings.** Changing Secure Boot state
shifts the TPM measurements that BitLocker relies on. Windows may demand your 48-digit
recovery key on the very next boot. If you don't have it, your Windows drive is locked.

Find your key at: **account.microsoft.com/devices/recoverykey**

Or from an admin PowerShell:

```powershell
manage-bde -protectors -get C:
```

Save the key somewhere other than that laptop (phone, paper, another machine).

### Step 1 — Check Secure Boot state

```
msinfo32
```

Look for **Secure Boot State** under System Summary. If it says **On**, you must either
disable it or sign the binary before it will boot.

### Step 2 — Check your EFI partition size

From an admin PowerShell:

```powershell
Get-Partition | Where-Object IsSystem | Select-Object DiskNumber, PartitionNumber, @{n='SizeMB';e={[math]::Round($_.Size/1MB)}}
```

Or from an admin Command Prompt:

```
diskpart
list disk
select disk 0
list partition   # look for Type: System
exit
```

rescue-mini (~150 MB) fits on most OEM ESPs. rescue-full (~700 MB) almost certainly
does not — use mini for on-disk install.

---

### Permanent on-disk install

Installing rescue.efi permanently on the EFI partition so it appears in your firmware
boot menu requires signing the binary, copying it to the ESP, and registering a boot
entry. These steps need Linux tools (`sbsign`, `mokutil`, `efibootmgr`) and access to
EFI NVRAM variables.

**Boot a Linux live USB** (Ubuntu, Fedora, or any distro) to run all steps below.
WSL2 can sign the binary but cannot write to EFI NVRAM, so `efibootmgr` and `mokutil`
will not work from it.

**Step 1: Disable Secure Boot**

Suspend BitLocker first so Windows doesn't demand the recovery key:

```powershell
# Admin PowerShell — suspends protection for one reboot only
Suspend-BitLocker -MountPoint C: -RebootCount 1
```

Then reboot into firmware settings. Fastest path on Windows 10/11:
**Settings → System → Recovery → Advanced startup → Restart now →
Troubleshoot → Advanced options → UEFI Firmware Settings → Restart**
(Or press F2 / Del / F10 / Esc at POST — varies by OEM.)

Find **Secure Boot** and set it to **Disabled**. Save and exit.

**Step 2: Sign and install from Linux**

```bash
# Find your EFI partition (usually the first partition, ~100-512 MB, type vfat)
lsblk -f

# Mount it
mkdir /mnt/efi
mount /dev/nvme0n1p1 /mnt/efi   # adjust device as shown by lsblk

# Generate a signing key
mkdir -p /root/rescue-keys
openssl req -newkey rsa:2048 -nodes -keyout /root/rescue-keys/rescue.key \
    -new -x509 -sha256 -days 3650 \
    -subj "/CN=Rescue EFI Signing Key/" \
    -out /root/rescue-keys/rescue.crt
openssl x509 -in /root/rescue-keys/rescue.crt -outform DER \
    -out /root/rescue-keys/rescue.cer

# Copy and sign the binary
mkdir -p /mnt/efi/EFI/rescue
cp /path/to/rescue-mini.efi /mnt/efi/EFI/rescue/rescue.efi
sbsign --key /root/rescue-keys/rescue.key \
       --cert /root/rescue-keys/rescue.crt \
       --output /mnt/efi/EFI/rescue/rescue.efi \
       /mnt/efi/EFI/rescue/rescue.efi

# Register the boot entry
efibootmgr --create --disk /dev/nvme0n1 --part 1 \
    --label "Rescue EFI" --loader '\EFI\rescue\rescue.efi'

# Enroll your signing key — set a short one-time password when prompted
mokutil --import /root/rescue-keys/rescue.cer
```

> **Getting the binary:** in the Linux live environment, download it directly:
> `curl -LO https://github.com/prithivirajasingh5/uki/releases/latest/download/rescue-mini.efi`
> or copy it from a FAT32 USB stick you prepared on Windows.

> **Keep `rescue.key` safe.** Save it to a location that survives the session — your Windows
> drive (accessible in WSL2 at `/mnt/c/`) or another machine. If you lose the key you'll
> need to generate a new one and re-enroll it.

**Step 3: Reboot into MokManager**

On the next boot, **MokManager** appears (blue screen). Enter the password you set,
select **Enroll MOK → Continue → Yes → Reboot**.

**Step 4: Re-enable Secure Boot**

Go back into firmware settings and re-enable Secure Boot. rescue.efi is now signed
with a key your firmware trusts and will boot normally.

**Updating rescue.efi later:**

Re-sign with the same key, then copy — the boot entry and enrolled certificate stay
valid:

```bash
sbsign --key rescue.key --cert rescue.crt \
       --output rescue-mini.efi rescue-mini.efi
# then copy to EFI partition as before
```

---

### Risk summary

| Action | Risk | How to avoid it |
|---|---|---|
| Change Secure Boot in firmware | BitLocker demands recovery key on next Windows boot | Back up recovery key first; suspend BitLocker before entering firmware |
| Enroll a MOK key | TPM PCR values shift, BitLocker may trigger | Same — suspend BitLocker before rebooting into MokManager |
| Copy files to EFI partition | Accidental overwrite of Windows bootloader | Only write to `EFI\rescue\` — never touch `EFI\Microsoft\` |
| Lose `rescue.key` | Can't sign updated rescue.efi; must re-enroll a new key | Copy key off the rescue environment to USB or another machine before rebooting |
| Skip the recovery key backup | Permanent data loss if BitLocker triggers and key is unknown | Always back up first — takes 30 seconds at account.microsoft.com/devices/recoverykey |

---

## What's inside

*Full variant. Mini includes only the disk / EFI repair subset (partitioning, btrfs, e2fs, dosfs, nvme, efibootmgr, nano, pciutils).*

| Category | Tools | mini |
|---|---|:---:|
| Partitioning | `parted`, `gdisk` | ✓ |
| Filesystems | `btrfs-progs`, `e2fsprogs`, `dosfstools`, `xfsprogs`, `ntfs-3g`, `exfatprogs` | btrfs/ext4/fat only |
| Encryption / LVM | `cryptsetup`, `lvm2` | — |
| NVMe | `nvme-cli` | ✓ |
| Disk health | `smartmontools`, `testdisk`, `ddrescue` | — |
| EFI boot repair | `efibootmgr`, `grub-efi-amd64-bin` | ✓ |
| WiFi | `iwd` + `iproute2` (no wpa_supplicant needed) | — |
| Networking | `dhclient`, `ping`, `traceroute`, `nc`, `tcpdump`, `ethtool`, `dig` | — |
| Remote access | `openssh-client`, `rsync` | — |
| Hardware info | `lshw`, `dmidecode`, `pciutils`, `usbutils` | `pciutils` only |
| Editors | `nano`, `vim-tiny` | `nano` only |
| Utilities | `curl`, `less`, `file`, `find`, `htop`, `lsof`, `strace` | `less`, `find` only |

Type `readme` at the rescue shell for a quick reference card.

---

## Manual build

```bash
git clone https://github.com/prithivirajasingh5/uki.git
cd uki
sudo make all     # builds both rescue-full.efi and rescue-mini.efi
sudo make full    # builds rescue-full.efi only
sudo make mini    # builds rescue-mini.efi only
```

Intermediate steps if you want finer control:

```bash
sudo make deps                  # check and install host build dependencies
sudo make rootfs VARIANT=mini   # debootstrap Debian into work/mini/rootfs/  (~5 min)
sudo make squashfs VARIANT=mini # compress to work/mini/root.squashfs         (~30 s)
sudo make initramfs VARIANT=mini
sudo make uki VARIANT=mini      # ukify → rescue-mini.efi
```

Each step is incremental — make only reruns a step if its inputs are newer than its output.

### Targeting a specific kernel

By default the build uses the latest kernel on the build host (`/boot/vmlinuz-*`).
To target a specific version:

```bash
sudo make full KERNEL=/boot/vmlinuz-6.8.0-51-generic
```

---

## Requirements

- Debian or Ubuntu, x86_64 (build host)
- Disk space: ~2 GB for full, ~500 MB for mini
- RAM on rescue target: ~2 GB for full, ~500 MB for mini
- UEFI firmware on the rescue target (BIOS/MBR is not supported)

The `make deps` step installs these build-time packages automatically:
`debootstrap`, `squashfs-tools`, `systemd-ukify`, `busybox-static`

---

## How it works

```
rescue.efi  (PE/EFI binary — one file)
  ├── .linux   → kernel image (from build host)
  ├── .initrd  → cpio.gz containing:
  │    ├── /init          POSIX sh script (PID 1)
  │    ├── busybox        static binary: sh, mount, switch_root …
  │    ├── unsquashfs     extracts the rootfs
  │    └── root.squashfs  compressed Debian rootfs (~200 MB uncompressed)
  └── .cmdline → console=ttyS0,115200 console=tty0
```

On boot:
1. UEFI loads `rescue.efi` and hands off to the kernel
2. The kernel runs `/init` (our script)
3. `init` mounts a tmpfs at `/newroot`, extracts `root.squashfs` into it, then calls `switch_root`
4. systemd starts in the fully writable Debian environment

See [`docs/design.md`](docs/design.md) for the full design rationale.

---

## WiFi

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

## Rebuilding after changes

```bash
cd ~/rescue-efi
sudo make all                       # rebuild both variants
sudo make full                      # rebuild full only
sudo make mini                      # rebuild mini only
sudo make uki VARIANT=full          # rebuild only the EFI (rootfs/squashfs unchanged)
sudo make clean && sudo make all    # full clean rebuild of both variants
```

---

## License

MIT
