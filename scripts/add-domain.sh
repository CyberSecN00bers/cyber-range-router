#!/bin/sh
set -eu

WAN_IF="${WAN_IF:-eth0}"
DOMAIN="${1:-}"

usage() {
  echo "Usage: $0 <domain_name>"
  echo "Example: $0 lab.cyber-range.local"
  exit 1
}

if [ -z "$DOMAIN" ]; then
  usage
fi

# Normalize: strip leading *., or leading dot
case "$DOMAIN" in
  \*.*) DOMAIN="${DOMAIN#*.}" ;;
  .*)   DOMAIN="${DOMAIN#.}" ;;
esac

if [ -z "$DOMAIN" ]; then
  echo "ERROR: invalid domain" >&2
  exit 1
fi

WAN_IP="${WAN_IP:-}"
if [ -z "$WAN_IP" ]; then
  WAN_IP="$(ip -4 addr show dev "$WAN_IF" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1 || true)"
fi

if [ -z "$WAN_IP" ]; then
  echo "ERROR: WAN IP not found on ${WAN_IF}" >&2
  exit 1
fi

CONF_DIR="/etc/dnsmasq.d"
mkdir -p "$CONF_DIR"

SAFE_NAME="$(echo "$DOMAIN" | sed 's/[^A-Za-z0-9._-]/_/g')"
CONF_FILE="${CONF_DIR}/domain-${SAFE_NAME}.conf"

cat > "$CONF_FILE" <<EOF
# Auto-generated: ${DOMAIN} -> ${WAN_IP}
address=/${DOMAIN}/${WAN_IP}
EOF

# Hot reload without full restart
if pidof dnsmasq >/dev/null 2>&1; then
  kill -HUP "$(pidof dnsmasq)" >/dev/null 2>&1 || true
else
  rc-service dnsmasq start >/dev/null 2>&1 || true
fi

echo "[OK] ${DOMAIN} -> ${WAN_IP} (dnsmasq reloaded)"
