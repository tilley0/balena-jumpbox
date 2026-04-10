#!/bin/sh
set -e

SSID="${MGMT_WIFI_SSID}"
PASSWORD="${MGMT_WIFI_PASSWORD}"
IFACE="${MGMT_WIFI_INTERFACE:-wlan0}"
CONNECTION_NAME="mgmt-wifi"

echo "=== WiFi Manager Service ==="

if [ -z "${SSID}" ]; then
    echo "MGMT_WIFI_SSID not set — skipping WiFi configuration"
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
    wifi-sec.psk "${PASSWORD}"

# Bring it up
echo "Connecting to ${SSID}..."
nmcli connection up "${CONNECTION_NAME}"

if [ $? -eq 0 ]; then
    echo "Connected to ${SSID} successfully"
    nmcli device show "${IFACE}" | grep -E "IP4\.(ADDRESS|GATEWAY|DNS)"
else
    echo "ERROR: Failed to connect to ${SSID}"
fi

# Stay alive — container restart on env var change will re-run this script
echo "WiFi manager idle. Change MGMT_WIFI_SSID to reconfigure."
sleep infinity
