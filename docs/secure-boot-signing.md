# Secure Boot Signing

By default `rescue.efi` is unsigned and will be rejected by firmware with Secure
Boot enabled. This guide shows how to sign it with your own key and enroll it.

## Prerequisites

```bash
sudo apt install sbsigntool openssl mokutil
```

## 1. Generate a signing key

```bash
mkdir -p keys && cd keys

# Generate a 2048-bit RSA key and self-signed certificate (valid 10 years)
openssl req -newkey rsa:2048 -nodes -keyout rescue.key \
    -new -x509 -sha256 -days 3650 \
    -subj "/CN=Rescue Image Signing Key/" \
    -out rescue.crt

# Convert to DER format for MOK enrollment
openssl x509 -in rescue.crt -outform DER -out rescue.cer

cd ..
```

## 2. Sign the UKI

Either sign as a post-build step:

```bash
sbsign --key keys/rescue.key --cert keys/rescue.crt \
       --output rescue.efi rescue.efi
```

Or let `ukify` sign during the build — add `--secureboot-private-key` and
`--secureboot-certificate` to `src/build-uki.sh`:

```bash
ukify build \
    --linux "$BOOT_KERNEL" \
    --initrd "$INITRAMFS" \
    --cmdline "$CMDLINE" \
    --secureboot-private-key keys/rescue.key \
    --secureboot-certificate keys/rescue.crt \
    --output "$OUTPUT"
```

Verify the signature:

```bash
sbverify --cert keys/rescue.crt rescue.efi && echo "signature OK"
```

## 3. Enroll the key (MOK)

Machine Owner Key (MOK) enrollment lets you add your own signing certificate
alongside the vendor keys without disabling Secure Boot.

Copy `keys/rescue.cer` to the EFI partition of the target machine, then:

```bash
# On the target machine:
sudo mokutil --import keys/rescue.cer
# Enter a one-time password when prompted

# Reboot — MokManager will appear and ask for the password
# Confirm "Enroll MOK" → reboot again
```

After enrollment `rescue.efi` will boot with Secure Boot active.

## 4. Verify enrollment

```bash
mokutil --list-enrolled | grep -A3 "CN=Rescue"
```

## Notes

- Keep `keys/rescue.key` private and off the rescue image itself.
- The `keys/` directory is gitignored by default — add it to `.gitignore` if
  you haven't already.
- For production use consider a hardware token (e.g. YubiKey via `pkcs11`) so
  the private key never touches disk.
