#!/bin/sh
set -e

PORT="${SSH_PORT:-2223}"
PASSWORD="${SSH_PASSWORD:-jumpbox}"

echo "=== SSH Jumpbox Service ==="
echo "Port: ${PORT}"

# Generate host keys if they don't exist
ssh-keygen -A

# Set root password
echo "root:${PASSWORD}" | chpasswd

# Configure sshd
cat > /etc/ssh/sshd_config <<EOF
Port ${PORT}
ListenAddress 0.0.0.0
PermitRootLogin yes
PasswordAuthentication yes
AllowTcpForwarding yes
GatewayPorts no
X11Forwarding no
PrintMotd yes
EOF

# Create a useful MOTD
cat > /etc/motd <<'EOF'

  =============================================
  Balena Jumpbox — Datacenter Configuration
  =============================================
  AP Network:     10.0.0.0/24  (wlan1)
  Server Network: 192.168.100.0/24  (eth0)

  Useful commands:
    View DHCP leases:  cat /data/leases/dnsmasq.leases
    Scan network:      nmap -sn 192.168.100.0/24
    SSH to server:     ssh <user>@192.168.100.x
    Dashboard:         http://10.0.0.1:8080

EOF

echo "Starting sshd on port ${PORT}..."
exec /usr/sbin/sshd -D -e
