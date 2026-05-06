# WiFi Setup in the Rescue Environment

The rescue system uses `iwd` (iNet Wireless Daemon) — lightweight, no wpa_supplicant needed.
`iwd` is configured with `EnableNetworkConfiguration=true`, so it handles DHCP and IPv6
automatically after association. No separate `dhclient` call required.

## Connect to a network

```bash
iwctl
  device list                        # find your interface, e.g. wlan0
  station wlan0 scan
  station wlan0 get-networks         # see available networks
  station wlan0 connect "MyNetwork"  # prompts for passphrase
  quit
```

Wait a second, then verify you have an IP:

```bash
ip addr show wlan0
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

The rescue image includes `openssh-client` but not `openssh-server`. To SSH *into*
the rescue system, install the server at runtime:

```bash
apt-get update && apt-get install -y openssh-server
systemctl start ssh
ip addr show   # find your IP
```

## Hidden networks

```bash
iwctl
  station wlan0 connect-hidden "HiddenSSID"
  quit
```

## Static IP (no DHCP)

Disable iwd's built-in network configuration for the interface, then assign manually:

```bash
ip addr add 192.168.1.50/24 dev wlan0
ip link set wlan0 up
ip route add default via 192.168.1.1
echo "nameserver 1.1.1.1" > /etc/resolv.conf
```

## Notes

- iwd stores profiles in `/var/lib/iwd/` for the duration of the session (tmpfs).
  Nothing persists across reboots — the system always starts fresh.
- DNS is pre-configured to `8.8.8.8` / `1.1.1.1` in `/etc/resolv.conf`.
