#!/bin/sh
set -e

IFACE="${AP_INTERFACE:-wlan1}"
IP="${AP_IP:-10.0.0.1}"
NETMASK="${AP_NETMASK:-255.255.255.0}"
SSID="${AP_SSID:-ct-jump}"
PASSWORD="${AP_PASSWORD}"
CHANNEL="${AP_CHANNEL:-6}"
DHCP_RANGE="${AP_DHCP_RANGE:-10.0.0.10,10.0.0.50,12h}"
ETH="${ETH_INTERFACE:-eth0}"

echo "=== WiFi AP Service ==="
echo "Interface: ${IFACE}"
echo "SSID: ${SSID}"
echo "IP: ${IP}"

# Wait for the USB WiFi adapter to appear
echo "Waiting for ${IFACE}..."
TRIES=0
while [ ! -d "/sys/class/net/${IFACE}" ]; do
    TRIES=$((TRIES + 1))
    if [ "$TRIES" -gt 30 ]; then
        echo "ERROR: ${IFACE} not found after 30s"
        echo "Available interfaces:"
        ls /sys/class/net/
        exit 1
    fi
    sleep 1
done
echo "${IFACE} detected"

# Release interface from NetworkManager before hostapd takes over
echo "Releasing ${IFACE} from NetworkManager..."
nmcli device disconnect "${IFACE}" 2>/dev/null || true
nmcli device set "${IFACE}" managed no 2>/dev/null || true
echo "${IFACE} is now unmanaged by NetworkManager"

# Kill any existing wpa_supplicant on this interface
if [ -f "/var/run/wpa_supplicant/${IFACE}" ]; then
    rm -f "/var/run/wpa_supplicant/${IFACE}"
fi

# Configure the AP interface
ip link set "${IFACE}" down || true
ip addr flush dev "${IFACE}" || true
ip addr add "${IP}/${NETMASK}" dev "${IFACE}"
ip link set "${IFACE}" up

# Generate hostapd config
cat > /etc/hostapd.conf <<EOF
interface=${IFACE}
driver=nl80211
ssid=${SSID}
hw_mode=g
channel=${CHANNEL}
ieee80211n=1
wmm_enabled=1
ht_capab=[HT40][SHORT-GI-20][SHORT-GI-40]
auth_algs=1
wpa=2
wpa_passphrase=${PASSWORD}
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# Set up NAT: laptop traffic on wlan1 masquerades out eth0
iptables -t nat -A POSTROUTING -o "${ETH}" -j MASQUERADE
iptables -A FORWARD -i "${IFACE}" -o "${ETH}" -j ACCEPT
iptables -A FORWARD -i "${ETH}" -o "${IFACE}" -m state --state RELATED,ESTABLISHED -j ACCEPT

# Run dnsmasq for AP-side DHCP (laptop gets an address)
# Use --listen-address to avoid port 53 conflict with BalenaOS DNS
# Use --port=0 to disable DNS server (not needed, just DHCP)
mkdir -p /data/ap-leases
dnsmasq \
    --interface="${IFACE}" \
    --listen-address="${IP}" \
    --bind-interfaces \
    --dhcp-range="${DHCP_RANGE}" \
    --dhcp-option=option:router,"${IP}" \
    --dhcp-option=option:dns-server,8.8.8.8,8.8.4.4 \
    --dhcp-leasefile=/data/ap-leases/dnsmasq.leases \
    --port=0 \
    --no-daemon &
DNSMASQ_PID=$!

echo "Starting hostapd on ${IFACE}..."
hostapd /etc/hostapd.conf &
HOSTAPD_PID=$!

# Wait for either process to exit
wait -n ${HOSTAPD_PID} ${DNSMASQ_PID} 2>/dev/null || wait ${HOSTAPD_PID}
