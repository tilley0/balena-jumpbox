#!/bin/sh
set -e

IFACE="${ETH_INTERFACE:-eth0}"
IP="${ETH_IP:-192.168.100.1}"
NETMASK="${ETH_NETMASK:-255.255.255.0}"
DHCP_RANGE="${ETH_DHCP_RANGE:-192.168.100.10,192.168.100.200,12h}"
DNS="${ETH_DNS:-8.8.8.8,8.8.4.4}"

echo "=== DHCP Service ==="
echo "Interface: ${IFACE}"
echo "IP: ${IP}"
echo "DHCP Range: ${DHCP_RANGE}"

# Wait for eth0
echo "Waiting for ${IFACE}..."
TRIES=0
while [ ! -d "/sys/class/net/${IFACE}" ]; do
    TRIES=$((TRIES + 1))
    if [ "$TRIES" -gt 30 ]; then
        echo "ERROR: ${IFACE} not found after 30s"
        exit 1
    fi
    sleep 1
done

# Wait for eth0 to be unmanaged by NetworkManager (wifi-manager handles this)
echo "Waiting for ${IFACE} to be released from NetworkManager..."
TRIES=0
while ip addr show dev "${IFACE}" 2>/dev/null | grep -q "dynamic"; do
    TRIES=$((TRIES + 1))
    if [ "$TRIES" -gt 30 ]; then
        echo "WARNING: ${IFACE} may still have a dynamic address, proceeding anyway"
        break
    fi
    sleep 1
done

# Assign static IP to eth0 (server-facing side)
ip addr flush dev "${IFACE}" || true
ip addr add "${IP}/${NETMASK}" dev "${IFACE}"
ip link set "${IFACE}" up
echo "${IFACE} configured with ${IP}/${NETMASK}"

# Generate dnsmasq config
cat > /etc/dnsmasq.conf <<EOF
interface=${IFACE}
bind-interfaces
dhcp-range=${DHCP_RANGE}
dhcp-option=option:router,${IP}
dhcp-option=option:dns-server,${DNS}
dhcp-leasefile=/data/leases/dnsmasq.leases
log-dhcp
log-queries
EOF

mkdir -p /data/leases

echo "Starting dnsmasq on ${IFACE}..."
exec dnsmasq --no-daemon --conf-file=/etc/dnsmasq.conf
