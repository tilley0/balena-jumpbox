#!/bin/sh
set -e

PORT="${DASHBOARD_PORT:-8080}"

echo "=== Dashboard Service ==="
echo "Listening on port ${PORT}"

exec python3 /usr/local/bin/app.py
