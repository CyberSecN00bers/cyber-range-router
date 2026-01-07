#!/bin/sh

# Tên script: qm-vlan
# Chức năng: Quản lý VLAN + Auto DHCP (Dnsmasq)
# Usage: qm-vlan add <vlan-id> <gateway-ip/cidr>
#        qm-vlan del <vlan-id>

CMD=$1
VID=$2
INPUT_IP=$3  # Ví dụ: 192.168.10.1/24

usage() {
    echo "Usage:"
    echo "  qm-vlan add <vlan_id> <gateway_ip/cidr>"
    echo "    Ex: qm-vlan add 10 192.168.10.1/24"
    echo "    (Tự động bật DHCP range .100 -> .200)"
    echo "  qm-vlan del <vlan_id>"
    exit 1
}

# Validate input cơ bản
if [ -z "$CMD" ] || [ -z "$VID" ]; then
    usage
fi

IFACE="eth1.${VID}"
NET_CONF="/etc/network/interfaces.d/vlan${VID}.conf"
DNS_CONF="/etc/dnsmasq.d/vlan${VID}.conf"

case "$CMD" in
    add)
        if [ -z "$INPUT_IP" ]; then
            echo "Error: Thiếu IP Gateway (vd: 192.168.10.1/24)"
            usage
        fi

        # Tách IP và Subnet (Giả sử nhập đúng format CIDR)
        # Lấy phần IP bỏ CIDR: 192.168.10.1
        IP_ONLY=$(echo $INPUT_IP | cut -d'/' -f1)
        # Lấy 3 octet đầu: 192.168.10
        SUBNET_PREFIX=$(echo $IP_ONLY | cut -d'.' -f1-3)
        
        echo "[+] Đang tạo VLAN $VID ($IFACE) với IP $INPUT_IP..."

        # 1. Tạo file config Network
        cat > "$NET_CONF" <<EOF
auto $IFACE
iface $IFACE inet static
    address $INPUT_IP
    vlan-raw-device eth1
EOF

        # 2. Tạo file config DHCP (Dnsmasq)
        # Tự động set range từ .100 đến .200
        echo "[+] Config DHCP: Range $SUBNET_PREFIX.100 -> .200"
        cat > "$DNS_CONF" <<EOF
# Auto-generated for VLAN $VID
interface=$IFACE
dhcp-range=$SUBNET_PREFIX.100,$SUBNET_PREFIX.200,255.255.255.0,24h
dhcp-option=tag:$IFACE,option:router,$IP_ONLY
dhcp-option=tag:$IFACE,option:dns-server,8.8.8.8
EOF

        # 3. Apply
        echo "[+] Kích hoạt interface..."
        ifup "$IFACE"
        
        echo "[+] Restarting DNS/DHCP service..."
        rc-service dnsmasq restart

        echo "[OK] VLAN $VID đã sẵn sàng!"
        ;;

    del)
        echo "[-] Đang xoá VLAN $VID..."
        
        # Hạ interface
        ifdown "$IFACE" 2>/dev/null
        
        # Xoá config Network
        if [ -f "$NET_CONF" ]; then
            rm "$NET_CONF"
            echo " - Deleted network config."
        fi

        # Xoá config DHCP
        if [ -f "$DNS_CONF" ]; then
            rm "$DNS_CONF"
            echo " - Deleted DHCP config."
        fi
        
        # Restart lại service để xoá cache
        rc-service dnsmasq restart
        echo "[OK] Đã xoá xong."
        ;;
    *)
        usage
        ;;
esac
