#!/usr/bin/env python3
"""Jumpbox dashboard — shows DHCP leases and connected hosts."""

import base64
import os
import time
from http.server import HTTPServer, BaseHTTPRequestHandler

PORT = int(os.environ.get("DASHBOARD_PORT", "8080"))
USER = os.environ.get("DASHBOARD_USER", "admin")
PASSWORD = os.environ.get("DASHBOARD_PASSWORD", "jumpbox")
LEASES_FILE = "/data/leases/dnsmasq.leases"


def check_auth(handler):
    auth_header = handler.headers.get("Authorization", "")
    if not auth_header.startswith("Basic "):
        return False
    decoded = base64.b64decode(auth_header[6:]).decode("utf-8")
    return decoded == f"{USER}:{PASSWORD}"


def parse_leases():
    leases = []
    try:
        with open(LEASES_FILE, "r") as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) >= 4:
                    expiry = int(parts[0])
                    mac = parts[1]
                    ip = parts[2]
                    hostname = parts[3] if parts[3] != "*" else "(unknown)"
                    leases.append({
                        "expiry": expiry,
                        "mac": mac.upper(),
                        "ip": ip,
                        "hostname": hostname,
                    })
    except FileNotFoundError:
        pass
    return leases


def classify_mac(mac):
    """Guess device type from MAC OUI prefix."""
    oui = mac[:8].upper()
    idrac_ouis = {
        "D0:94:66", "F4:02:70", "F8:BC:12", "50:9A:4C",
        "18:66:DA", "B0:83:FE", "4C:D9:8F", "F0:1F:AF",
    }
    if oui in idrac_ouis:
        return "iDRAC"
    return "Server/NIC"


def render_html(leases):
    now = int(time.time())
    rows = ""
    for l in sorted(leases, key=lambda x: x["ip"]):
        remaining = l["expiry"] - now
        if remaining > 0:
            hours = remaining // 3600
            minutes = (remaining % 3600) // 60
            ttl = f"{hours}h {minutes}m"
        else:
            ttl = "expired"
        device_type = classify_mac(l["mac"])
        rows += f"""
        <tr>
            <td>{l['ip']}</td>
            <td><code>{l['mac']}</code></td>
            <td>{l['hostname']}</td>
            <td>{device_type}</td>
            <td>{ttl}</td>
        </tr>"""

    if not rows:
        rows = '<tr><td colspan="5" style="text-align:center;color:#888;">No leases yet</td></tr>'

    return f"""<!DOCTYPE html>
<html>
<head>
    <title>Jumpbox Dashboard</title>
    <meta http-equiv="refresh" content="10">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body {{
            font-family: -apple-system, system-ui, sans-serif;
            margin: 0; padding: 20px;
            background: #1a1a2e; color: #e0e0e0;
        }}
        h1 {{ color: #00d4aa; margin-bottom: 5px; }}
        .subtitle {{ color: #888; margin-bottom: 20px; }}
        table {{
            width: 100%; border-collapse: collapse;
            background: #16213e; border-radius: 8px;
            overflow: hidden;
        }}
        th {{
            background: #0f3460; color: #00d4aa;
            padding: 12px 16px; text-align: left;
        }}
        td {{ padding: 10px 16px; border-bottom: 1px solid #1a1a2e; }}
        tr:hover {{ background: #1a2744; }}
        code {{ background: #0f3460; padding: 2px 6px; border-radius: 3px; }}
        .stats {{
            display: flex; gap: 20px; margin-bottom: 20px;
        }}
        .stat {{
            background: #16213e; padding: 15px 20px;
            border-radius: 8px; border-left: 3px solid #00d4aa;
        }}
        .stat-value {{ font-size: 24px; font-weight: bold; color: #00d4aa; }}
        .stat-label {{ font-size: 12px; color: #888; }}
    </style>
</head>
<body>
    <h1>Jumpbox Dashboard</h1>
    <div class="subtitle">Auto-refreshes every 10 seconds</div>
    <div class="stats">
        <div class="stat">
            <div class="stat-value">{len(leases)}</div>
            <div class="stat-label">Connected Hosts</div>
        </div>
        <div class="stat">
            <div class="stat-value">{sum(1 for l in leases if classify_mac(l['mac']) == 'iDRAC')}</div>
            <div class="stat-label">iDRAC Interfaces</div>
        </div>
        <div class="stat">
            <div class="stat-value">{sum(1 for l in leases if classify_mac(l['mac']) != 'iDRAC')}</div>
            <div class="stat-label">Server NICs</div>
        </div>
    </div>
    <table>
        <thead>
            <tr>
                <th>IP Address</th>
                <th>MAC Address</th>
                <th>Hostname</th>
                <th>Type</th>
                <th>Lease TTL</th>
            </tr>
        </thead>
        <tbody>{rows}
        </tbody>
    </table>
</body>
</html>"""


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if not check_auth(self):
            self.send_response(401)
            self.send_header("WWW-Authenticate", 'Basic realm="Jumpbox"')
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"Unauthorized")
            return

        leases = parse_leases()
        html = render_html(leases)
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.end_headers()
        self.wfile.write(html.encode())

    def log_message(self, format, *args):
        print(f"[dashboard] {args[0]}")


if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", PORT), Handler)
    print(f"Dashboard running on port {PORT}")
    server.serve_forever()
