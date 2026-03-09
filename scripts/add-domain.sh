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

# Debounced restart to avoid thrash on multi-user updates
schedule_dnsmasq_restart() {
  delay="${DNSMASQ_RESTART_DELAY:-4}"
  lock_dir="/run/dnsmasq-restart.lock"
  pid_file="/run/dnsmasq-restart.pid"

  # If a restart is already scheduled, do nothing
  if [ -d "$lock_dir" ]; then
    if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file" 2>/dev/null)" 2>/dev/null; then
      return 0
    fi
    # Stale lock, clean it
    rm -f "$pid_file" >/dev/null 2>&1 || true
    rmdir "$lock_dir" >/dev/null 2>&1 || true
  fi

  if mkdir "$lock_dir" 2>/dev/null; then
    (
      sleep "$delay"
      rc-service dnsmasq restart >/dev/null 2>&1 || true
      rm -f "$pid_file" >/dev/null 2>&1 || true
      rmdir "$lock_dir" >/dev/null 2>&1 || true
    ) &
    echo $! > "$pid_file" 2>/dev/null || true
  fi
}

STATUS_MSG="dnsmasq restart scheduled"
if pidof dnsmasq >/dev/null 2>&1; then
  schedule_dnsmasq_restart
else
  rc-service dnsmasq start >/dev/null 2>&1 || true
  STATUS_MSG="dnsmasq started"
fi

echo "[OK] ${DOMAIN} -> ${WAN_IP} (${STATUS_MSG})"
