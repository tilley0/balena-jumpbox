#!/bin/sh
set -e

SSID="${MGMT_WIFI_SSID}"
PASSWORD="${MGMT_WIFI_PASSWORD}"
IFACE="${MGMT_WIFI_INTERFACE:-wlan0}"
ETH="${ETH_INTERFACE:-eth0}"
AP_IFACE="${AP_INTERFACE:-wlp1s0u1u2}"
CONNECTION_NAME="mgmt-wifi"

echo "=== WiFi Manager Service ==="

# ---------------------------------------------------------------
# Disconnect eth0 from NetworkManager so our dhcp container owns it.
# This prevents BalenaOS from using eth0 as a management uplink.
# ---------------------------------------------------------------
echo "Releasing eth0 from NetworkManager..."

# Disconnect any active connection on eth0
nmcli device disconnect "${ETH}" 2>/dev/null || true

# Delete any existing NetworkManager connection profiles for eth0
for conn in $(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | grep ":${ETH}$" | cut -d: -f1); do
    echo "Deleting connection '${conn}' on ${ETH}"
    nmcli connection delete "${conn}" 2>/dev/null || true
done

# Set eth0 to unmanaged by NetworkManager
nmcli device set "${ETH}" managed no 2>/dev/null || true
echo "${ETH} is now unmanaged by NetworkManager"

# ---------------------------------------------------------------
# Release USB WiFi adapter from NetworkManager so hostapd owns it.
# NetworkManager will fight hostapd for control otherwise.
# ---------------------------------------------------------------
echo "Releasing ${AP_IFACE} from NetworkManager..."
nmcli device disconnect "${AP_IFACE}" 2>/dev/null || true
nmcli device set "${AP_IFACE}" managed no 2>/dev/null || true
echo "${AP_IFACE} is now unmanaged by NetworkManager"

# ---------------------------------------------------------------
# Configure management WiFi on wlan0
# ---------------------------------------------------------------
if [ -z "${SSID}" ]; then
    echo "MGMT_WIFI_SSID not set -- skipping WiFi configuration"
    echo "Set MGMT_WIFI_SSID and MGMT_WIFI_PASSWORD in Balena Cloud to configure"
    sleep infinity
fi

echo "Configuring ${IFACE} to connect to SSID: ${SSID}"

# Remove any existing managed connection with this name
nmcli connection delete "${CONNECTION_NAME}" 2>/dev/null || true

# Create the new WiFi connection on wlan0
nmcli connection add \
    type wifi \
    ifname "${IFACE}" \
    con-name "${CONNECTION_NAME}" \
    ssid "${SSID}" \
    wifi-sec.key-mgmt wpa-psk \
    wifi-sec.psk "${PASSWORD}" \
    connection.autoconnect yes \
    ipv4.route-metric 100

# Set WiFi as preferred route (lower metric = higher priority)
# This ensures Balena Cloud traffic goes over WiFi, not eth0
nmcli connection modify "${CONNECTION_NAME}" ipv4.route-metric 100

# Bring it up
echo "Connecting to ${SSID}..."
if nmcli connection up "${CONNECTION_NAME}"; then
    echo "Connected to ${SSID} successfully"
    nmcli device show "${IFACE}" | grep -E "IP4\.(ADDRESS|GATEWAY|DNS)"
else
    echo "ERROR: Failed to connect to ${SSID}"
fi

echo ""
echo "Network summary:"
nmcli device status
echo ""
echo "Default route:"
ip route show default

# Stay alive -- container restart on env var change will re-run this script
echo ""
echo "WiFi manager idle. Change MGMT_WIFI_SSID to reconfigure."
sleep infinity
