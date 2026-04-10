# Balena Jumpbox

A portable wireless access point, DHCP server, and SSH jumpbox for initial datacenter server configuration. Runs on a Raspberry Pi 4 managed by [Balena Cloud](https://www.balena.io/).

## Architecture

```
                                    ┌──────────────────────────┐
                                    │     Raspberry Pi 4       │
                                    │                          │
[Your Laptop] ── WiFi (ct-jump) ──▶ │ wlan1 (USB)    10.0.0.1 │
                                    │    hostapd + NAT         │
                                    │                          │
                                    │ eth0          192.168.100.1 │──▶ [Temp Switch] ──▶ [Servers]
                                    │    DHCP server           │                   ──▶ [iDRAC]
                                    │                          │
                                    │ wlan0 (onboard)          │──▶ [Management WiFi] ──▶ Balena Cloud
                                    └──────────────────────────┘
```

| Interface | Role | Network |
|-----------|------|---------|
| `wlan0` (onboard) | BalenaOS management — connects to site WiFi for Balena Cloud | Varies by location |
| `wlan1` (USB adapter) | Access point — your laptop connects here | `10.0.0.0/24` |
| `eth0` | Wired to datacenter switch — serves DHCP to servers and iDRAC | `192.168.100.0/24` |

## Services

| Service | Purpose |
|---------|---------|
| **wifi-ap** | Runs hostapd on the USB WiFi adapter, serves DHCP to WiFi clients, NATs traffic to eth0 |
| **dhcp** | Runs dnsmasq on eth0, assigns IPs to servers and iDRAC interfaces |
| **ssh-jumpbox** | OpenSSH server for proxying into datacenter hosts, includes nmap |
| **wifi-manager** | Configures the onboard wlan0 management WiFi via Balena Cloud env vars |
| **dashboard** | Web UI showing connected hosts and DHCP leases (port 8080) |

## Prerequisites

- Raspberry Pi 4 with a USB WiFi adapter (must support AP mode)
- SD card imaged with BalenaOS, registered to a Balena Cloud fleet
- [Balena CLI](https://docs.balena.io/reference/balena-cli/) installed: `brew install balena-cli`

## Quick Start

### 1. Deploy the application

```bash
balena login
balena push gh_ctilley/jumpbox
```

### 2. Set environment variables

In the Balena Cloud dashboard, go to **Device > Device Variables** and set:

| Variable | Value | Required |
|----------|-------|----------|
| `AP_SSID` | `ct-jump` | Yes |
| `AP_PASSWORD` | WiFi password for the AP | Yes |
| `SSH_PASSWORD` | Password for SSH access | Yes |
| `MGMT_WIFI_SSID` | Management WiFi SSID | Optional |
| `MGMT_WIFI_PASSWORD` | Management WiFi password | Optional |

Or via CLI:

```bash
balena env add AP_SSID ct-jump --device pretty-pine
balena env add AP_PASSWORD 'your-wifi-password' --device pretty-pine
balena env add SSH_PASSWORD 'your-ssh-password' --device pretty-pine
```

### 3. Connect from your laptop

```bash
# Join the "ct-jump" WiFi network, then:
ssh root@10.0.0.1 -p 22222
```

### 4. Access servers

From the jumpbox:

```bash
# View DHCP leases
cat /data/leases/dnsmasq.leases

# Scan the server network
nmap -sn 192.168.100.0/24

# SSH to a server
ssh root@192.168.100.x
```

Or directly from your laptop using ProxyJump:

```bash
ssh -J root@10.0.0.1:22222 root@192.168.100.x
```

### 5. Access the dashboard

Open `http://10.0.0.1:8080` in your browser while connected to the ct-jump WiFi. Log in with `admin` / your `SSH_PASSWORD`.

### 6. Access iDRAC web UI

Open `https://192.168.100.x` in your browser while connected to ct-jump WiFi. Traffic routes through the Pi automatically.

## Environment Variables Reference

### Required

| Variable | Default | Description |
|----------|---------|-------------|
| `AP_SSID` | `ct-jump` | SSID broadcast by the USB WiFi adapter |
| `AP_PASSWORD` | *(none)* | WPA2 password for the AP |
| `SSH_PASSWORD` | *(none)* | Root password for the SSH jumpbox |

### WiFi AP (wifi-ap)

| Variable | Default | Description |
|----------|---------|-------------|
| `AP_CHANNEL` | `6` | WiFi channel |
| `AP_INTERFACE` | `wlan1` | USB WiFi adapter interface name |
| `AP_IP` | `10.0.0.1` | IP address of the AP interface |
| `AP_NETMASK` | `255.255.255.0` | AP subnet mask |
| `AP_DHCP_RANGE` | `10.0.0.10,10.0.0.50,12h` | DHCP range for WiFi clients |

### DHCP Server (dhcp)

| Variable | Default | Description |
|----------|---------|-------------|
| `ETH_INTERFACE` | `eth0` | Wired interface to datacenter switch |
| `ETH_IP` | `192.168.100.1` | IP address on the server network |
| `ETH_NETMASK` | `255.255.255.0` | Server subnet mask |
| `ETH_DHCP_RANGE` | `192.168.100.10,192.168.100.200,12h` | DHCP range for servers/iDRAC |
| `ETH_DNS` | `8.8.8.8,8.8.4.4` | DNS servers advertised to DHCP clients |

### SSH Jumpbox (ssh-jumpbox)

| Variable | Default | Description |
|----------|---------|-------------|
| `SSH_PORT` | `22222` | SSH listen port (avoids conflict with BalenaOS sshd) |

### Management WiFi (wifi-manager)

| Variable | Default | Description |
|----------|---------|-------------|
| `MGMT_WIFI_SSID` | *(none)* | SSID for Balena Cloud connectivity (phone hotspot, site WiFi) |
| `MGMT_WIFI_PASSWORD` | *(none)* | Password for the management WiFi |
| `MGMT_WIFI_INTERFACE` | `wlan0` | Onboard WiFi interface |

Changing `MGMT_WIFI_SSID` or `MGMT_WIFI_PASSWORD` in the Balena dashboard restarts the wifi-manager container, which reconfigures the onboard WiFi. The device must be online to receive the update.

### Dashboard (dashboard)

| Variable | Default | Description |
|----------|---------|-------------|
| `DASHBOARD_PORT` | `8080` | Web dashboard listen port |
| `DASHBOARD_USER` | `admin` | Basic auth username |
| `DASHBOARD_PASSWORD` | *(SSH_PASSWORD)* | Basic auth password |

## SSH Config (Laptop)

Add to `~/.ssh/config` for convenient access:

```
Host jumpbox
    HostName 10.0.0.1
    Port 22222
    User root

Host dc-*
    ProxyJump jumpbox
    User root
```

Then connect with `ssh dc-server-1` after mapping IPs in `/etc/hosts` or using the IP directly.

## Troubleshooting

### USB WiFi adapter not detected

Check the wifi-ap service logs in the Balena dashboard. If the adapter shows up as something other than `wlan1`, set `AP_INTERFACE` to the correct interface name. The logs will list available interfaces.

### AP mode not supported

Not all USB WiFi chipsets support AP mode. Check by SSHing into the BalenaOS host and running `iw list` — look for `AP` under "Supported interface modes". Realtek RTL8812AU/BU and Atheros-based adapters generally work.

### Can't reach servers from laptop

Verify the wifi-ap service is running and check its logs for iptables/NAT errors. Your laptop should get `10.0.0.1` as its default gateway from DHCP. Test with `ping 192.168.100.1` first (the Pi's eth0 address).

### Dashboard shows no leases

Servers must be set to DHCP on their primary NIC or iDRAC interface. Check the dhcp service logs for DHCPDISCOVER messages. If no requests are coming in, verify the physical cabling through the temporary switch.

### Management WiFi won't connect

The wifi-manager service logs will show the nmcli output. Verify the SSID and password are correct. If the device goes offline after a bad config, you can connect to its AP WiFi and SSH in to debug, or re-flash the SD card.
