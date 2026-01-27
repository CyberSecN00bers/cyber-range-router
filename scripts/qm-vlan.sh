#!/bin/sh
set -eu

# =========================
# script: qm-vlan
# function: VLAN management + DHCP (dnsmasq) + firewall allow list
# Usage:
#   qm-vlan add <vlan-id> <gateway-ip/cidr>
#   qm-vlan del <vlan-id>
# =========================

# MUST MATCH setup-network.sh
VLAN_CHAIN="QM_VLAN"
WAN_IF="eth0"
LAN_TRUNK="eth1"
DMZ_IF="eth1.99"

WAZUH_IP="${WAZUH_IP:-172.16.99.11}"
WAZUH_UI_MARK="${WAZUH_UI_MARK:-0x9443}"

# User VLAN range (change if you want)
USER_VID_MIN="${USER_VID_MIN:-100}"
USER_VID_MAX="${USER_VID_MAX:-200}"

# Marker block in /etc/network/interfaces
QM_BEGIN="### BEGIN QM-VLAN-SOURCES"
QM_END="### END QM-VLAN-SOURCES"

CMD="${1:-}"
VID="${2:-}"
INPUT_IP="${3:-}"   # e.g. 172.16.100.1/24

usage() {
  echo "Usage:"
  echo "  qm-vlan add <vlan_id> <gateway_ip/cidr>   (ex: qm-vlan add 100 172.16.100.1/24)"
  echo "  qm-vlan del <vlan_id>"
  exit 1
}

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: run as root" >&2
    exit 1
  fi
}

is_number() { echo "$1" | grep -Eq '^[0-9]+$'; }

ensure_chain() {
  iptables -N "$VLAN_CHAIN" 2>/dev/null || true
}

add_rule_once() {
  if ! iptables -C "$VLAN_CHAIN" "$@" 2>/dev/null; then
    iptables -A "$VLAN_CHAIN" "$@"
  fi
}

del_rule_all() {
  while iptables -C "$VLAN_CHAIN" "$@" 2>/dev/null; do
    iptables -D "$VLAN_CHAIN" "$@"
  done
}

svc_restart() {
  svc="$1"
  rc-service "$svc" restart >/dev/null 2>&1 || {
    rc-service "$svc" stop >/dev/null 2>&1 || true
    rc-service "$svc" start >/dev/null 2>&1 || true
  }
}

refresh_qm_sources() {
  interfaces="/etc/network/interfaces"
  [ -f "$interfaces" ] || { echo "ERROR: missing $interfaces (run setup-network.sh first)"; exit 1; }

  if ! grep -qF "$QM_BEGIN" "$interfaces"; then
    printf '\n# Auto-managed sources for qm-vlan (explicit, no wildcard)\n%s\n%s\n' "$QM_BEGIN" "$QM_END" >> "$interfaces"
  fi

  src_tmp="$(mktemp)"
  for f in /etc/network/interfaces.d/vlan*.conf; do
    [ -f "$f" ] || continue
    echo "source $f" >> "$src_tmp"
  done

  out_tmp="$(mktemp)"
  awk -v begin="$QM_BEGIN" -v end="$QM_END" -v sf="$src_tmp" '
    BEGIN { inblock=0 }
    $0==begin {
      print
      while ((getline line < sf) > 0) { print line }
      close(sf)
      inblock=1
      next
    }
    $0==end { inblock=0; print; next }

    inblock==0 {
      if ($1=="include") next
      if ($1=="source" && $2 ~ /^\/etc\/network\/interfaces\.d\/vlan[0-9]+\.conf$/) next
      print
    }
  ' "$interfaces" > "$out_tmp"

  cat "$out_tmp" > "$interfaces"
  rm -f "$out_tmp" "$src_tmp"
}

need_root
[ -n "$CMD" ] && [ -n "$VID" ] || usage
is_number "$VID" || { echo "ERROR: vlan_id must be number"; exit 1; }

# Reserve 10 & 99 (preconfigured)
if [ "$VID" = "10" ] || [ "$VID" = "99" ]; then
  echo "ERROR: VLAN $VID is reserved (already defined by setup-network.sh)." >&2
  exit 1
fi

# Enforce user VLAN range
if [ "$VID" -lt "$USER_VID_MIN" ] || [ "$VID" -gt "$USER_VID_MAX" ]; then
  echo "ERROR: VLAN $VID must be in range ${USER_VID_MIN}-${USER_VID_MAX} (change USER_VID_MIN/USER_VID_MAX to override)." >&2
  exit 1
fi

IFACE="${LAN_TRUNK}.${VID}"
NET_CONF="/etc/network/interfaces.d/vlan${VID}.conf"
DNS_CONF="/etc/dnsmasq.d/vlan${VID}.conf"

add_fw_rules() {
  ensure_chain

  # 1) Internet access (NAT via WAN)
  add_rule_once -i "$IFACE" -o "$WAN_IF" \
    -m conntrack --ctstate NEW,ESTABLISHED,RELATED \
    -m comment --comment "qm-${VID}-inet" -j ACCEPT

  # 2) Wazuh agent traffic only (no direct UI)
  add_rule_once -i "$IFACE" -o "$DMZ_IF" -d "$WAZUH_IP" -p tcp -m multiport --dports 1514,1515 \
    -m conntrack --ctstate NEW,ESTABLISHED,RELATED \
    -m comment --comment "qm-${VID}-wazuh-agent" -j ACCEPT

  # 3) Wazuh UI ONLY via WAN_IP:9443 hairpin mark (still blocks direct 172.16.99.11:443)
  add_rule_once -i "$IFACE" -o "$DMZ_IF" -d "$WAZUH_IP" -p tcp --dport 443 \
    -m conntrack --ctstate NEW -m connmark --mark "$WAZUH_UI_MARK" \
    -m comment --comment "qm-${VID}-wazuh-ui-via-wan" -j ACCEPT
}

del_fw_rules() {
  ensure_chain

  del_rule_all -i "$IFACE" -o "$WAN_IF" \
    -m conntrack --ctstate NEW,ESTABLISHED,RELATED \
    -m comment --comment "qm-${VID}-inet" -j ACCEPT

  del_rule_all -i "$IFACE" -o "$DMZ_IF" -d "$WAZUH_IP" -p tcp -m multiport --dports 1514,1515 \
    -m conntrack --ctstate NEW,ESTABLISHED,RELATED \
    -m comment --comment "qm-${VID}-wazuh-agent" -j ACCEPT

  del_rule_all -i "$IFACE" -o "$DMZ_IF" -d "$WAZUH_IP" -p tcp --dport 443 \
    -m conntrack --ctstate NEW -m connmark --mark "$WAZUH_UI_MARK" \
    -m comment --comment "qm-${VID}-wazuh-ui-via-wan" -j ACCEPT
}

case "$CMD" in
  add)
    [ -n "$INPUT_IP" ] || { echo "ERROR: Missing gateway_ip/cidr"; usage; }

    CIDR="$(echo "$INPUT_IP" | awk -F/ '{print $2}')"
    [ "$CIDR" = "24" ] || { echo "ERROR: only /24 is supported (you provided /$CIDR)"; exit 1; }

    IP_ONLY="$(echo "$INPUT_IP" | cut -d/ -f1)"
    SUBNET_PREFIX="$(echo "$IP_ONLY" | cut -d'.' -f1-3)"

    echo "[+] Creating VLAN $VID ($IFACE) gateway $INPUT_IP ..."

    mkdir -p /etc/network/interfaces.d /etc/dnsmasq.d

    cat > "$NET_CONF" <<EOF
auto $IFACE
iface $IFACE inet static
    address $INPUT_IP
    vlan-raw-device $LAN_TRUNK
EOF

    cat > "$DNS_CONF" <<EOF
# Auto-generated for VLAN $VID
interface=$IFACE
dhcp-range=$SUBNET_PREFIX.100,$SUBNET_PREFIX.200,255.255.255.0,24h
dhcp-option=tag:$IFACE,option:router,$IP_ONLY
dhcp-option=tag:$IFACE,option:dns-server,8.8.8.8
EOF

    echo "[+] Update /etc/network/interfaces (explicit source lines)..."
    refresh_qm_sources

    echo "[+] Bring interface up..."
    rc-service networking start >/dev/null 2>&1 || true
    ifup "$IFACE" >/dev/null 2>&1 || true

    echo "[+] Apply firewall allow-list..."
    add_fw_rules

    echo "[+] Restart dnsmasq..."
    svc_restart dnsmasq

    echo "[+] Save iptables..."
    /etc/init.d/iptables save >/dev/null 2>&1 || true

    echo "[OK] VLAN $VID ready."
    ;;

  del)
    echo "[-] Removing VLAN $VID ($IFACE)..."

    echo " - Remove firewall rules..."
    del_fw_rules

    ifdown "$IFACE" >/dev/null 2>&1 || true

    [ -f "$NET_CONF" ] && rm -f "$NET_CONF" && echo " - Deleted $NET_CONF"
    [ -f "$DNS_CONF" ] && rm -f "$DNS_CONF" && echo " - Deleted $DNS_CONF"

    echo " - Update /etc/network/interfaces (explicit source lines)..."
    refresh_qm_sources

    svc_restart dnsmasq
    /etc/init.d/iptables save >/dev/null 2>&1 || true

    echo "[OK] VLAN $VID removed."
    ;;

  *)
    usage
    ;;
esac
