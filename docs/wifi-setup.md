# WiFi Setup in the Rescue Environment

The rescue system uses `iwd` (iNet Wireless Daemon) — lightweight, no wpa_supplicant
daemon needed, works entirely from the command line.

## Connect to a network

```bash
# Start iwd if it isn't running
systemctl start iwd

# Open the interactive client
iwctl

# Inside iwctl:
device list                        # find your interface, e.g. wlan0
station wlan0 scan
station wlan0 get-networks         # see available networks
station wlan0 connect "MyNetwork"  # prompts for passphrase
exit
```

Wait a second, then verify:

```bash
ip link show wlan0
```

## Get an IP address

`iwd` doesn't manage DHCP — use `iproute2`:

```bash
# DHCP via systemd-networkd (simplest)
systemctl start systemd-networkd

# Or manually with dhclient if available:
dhclient wlan0

# Verify
ip addr show wlan0
ip route show
```

## Test connectivity

```bash
ping -c3 8.8.8.8
curl -s https://example.com | head -5
```

## SSH to another host

```bash
ssh user@192.168.1.1
```

The rescue image includes `openssh-client` but not `openssh-server`. If you need
to SSH *into* the rescue system, install the server at runtime:

```bash
# Requires network connectivity first
apt-get update && apt-get install -y openssh-server
systemctl start ssh
ip addr show   # find your IP
```

## Hidden networks

```bash
iwctl
station wlan0 connect-hidden "HiddenSSID"
```

## Static IP (no DHCP)

```bash
ip addr add 192.168.1.50/24 dev wlan0
ip link set wlan0 up
ip route add default via 192.168.1.1
echo "nameserver 1.1.1.1" > /etc/resolv.conf
```

## Persistent iwd config (within session)

iwd stores profiles in `/var/lib/iwd/`. They persist for the duration of the
boot session (tmpfs). Nothing survives a reboot — the system always starts fresh.
