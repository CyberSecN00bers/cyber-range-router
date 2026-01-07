#!/bin/sh

# Tên script: qm-vlan
# Chức năng: Quản lý VLAN trên eth1 nhanh chóng
# Usage: qm-vlan add <vlan-id> <ip/cidr>
#        qm-vlan del <vlan-id>

CMD=$1
VID=$2
ADDR=$3

usage() {
    echo "Usage:"
    echo "  qm-vlan add <vlan_id> <ip_cidr>  (Ex: qm-vlan add 10 192.168.10.1/24)"
    echo "  qm-vlan del <vlan_id>            (Ex: qm-vlan del 10)"
    exit 1
}

if [ -z "$CMD" ] || [ -z "$VID" ]; then
    usage
fi

CONF_FILE="/etc/network/interfaces.d/vlan${VID}.conf"
IFACE="eth1.${VID}"

case "$CMD" in
    add)
        if [ -z "$ADDR" ]; then
            echo "Error: Missing IP address for add command."
            usage
        fi
        
        echo "[+] Creating VLAN $VID with IP $ADDR..."
        
        # Tạo file config riêng cho VLAN này
        cat > "$CONF_FILE" <<EOF
auto $IFACE
iface $IFACE inet static
    address $ADDR
    vlan-raw-device eth1
EOF
        
        # Kích hoạt interface ngay lập tức
        ifup "$IFACE"
        
        # (Tuỳ chọn) Nếu bạn muốn DHCP server cho VLAN này thì thêm logic start dnsmasq ở đây
        echo "[OK] VLAN $VID ($IFACE) is UP."
        ;;
        
    del)
        echo "[-] Removing VLAN $VID..."
        
        # Hạ interface xuống
        ifdown "$IFACE" 2>/dev/null
        
        # Xoá file config
        if [ -f "$CONF_FILE" ]; then
            rm "$CONF_FILE"
            echo "[OK] Config removed."
        else
            echo "[!] Config file not found, but interface down command sent."
        fi
        ;;
        
    *)
        usage
        ;;
esac
