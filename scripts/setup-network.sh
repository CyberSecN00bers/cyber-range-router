#!/bin/sh
# Cấu hình IP Forwarding
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sysctl -w net.ipv4.ip_forward=1

# Cấu hình IPTABLES NAT (Overload ra eth0)
apk add iptables
rc-update add iptables default
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# Save rule
/etc/init.d/iptables save

# Cấu hình Interface vĩnh viễn (giữ eth1 manual để làm VLAN Trunk)
mkdir -p /etc/network/interfaces.d

cat > /etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

# WAN Interface
auto eth0
iface eth0 inet dhcp

# LAN Trunk Interface (Layer 2 only)
auto eth1
iface eth1 inet manual
    up ip link set dev eth1 up
    down ip link set dev eth1 down

# Load các cấu hình VLAN từ thư mục con
include /etc/network/interfaces.d/*.conf
EOF
