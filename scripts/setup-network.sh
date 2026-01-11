#!/bin/sh
# Cấu hình IP Forwarding
# sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -w net.ipv4.ip_forward=1

# Cấu hình IPTABLES NAT (Overload ra eth0)
apk add iptables
rc-update add iptables default

# NAT Overload for internet
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# NAT port
GUAC_IP="172.16.99.10"
iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 80 -j DNAT --to-destination $GUAC_IP:80
iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 443 -j DNAT --to-destination $GUAC_IP:443

# Cho phép gói tin mới (NEW) đi đến Guacamole qua port 80/443
iptables -A FORWARD -p tcp -d $GUAC_IP --dport 80 -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -p tcp -d $GUAC_IP --dport 443 -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT

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

# --- PRE-CONFIGURED VLAN 1 ---
auto eth1.10
iface eth1.10 inet static
    address 172.16.255.1
    netmask 255.255.255.0
    vlan-raw-device eth1

auto eth1.99
iface eth1.99 inet static
    address 172.16.99.1
    netmask 255.255.255.0
    vlan-raw-device eth1

# Load các cấu hình VLAN từ thư mục con
include /etc/network/interfaces.d/*.conf
EOF

apk add dnsmasq
rc-update add dnsmasq default

mkdir -p /etc/dnsmasq.d
mv /etc/dnsmasq.conf /etc/dnsmasq.conf.bak 2>/dev/null

cat > /etc/dnsmasq.conf <<EOF
# Base settings
domain-needed
bogus-priv
no-resolv
# DNS Upstream (Google/Cloudflare)
server=8.8.8.8
server=1.1.1.1

# Quan trọng: Chỉ bind vào các interface được khai báo cụ thể
bind-interfaces

# Load các file config DHCP của từng VLAN
conf-dir=/etc/dnsmasq.d,*.conf
EOF

cat > /etc/dnsmasq.d/vlan10.conf <<EOF
# Config cho eth1.10
interface=eth1.10
dhcp-range=172.16.255.100,172.16.255.200,255.255.255.0,24h
dhcp-option=tag:eth1.10,option:router,172.16.255.1
dhcp-option=tag:eth1.10,option:dns-server,8.8.8.8
EOF

cat > /etc/dnsmasq.d/vlan99.conf <<EOF
interface=eth1.99
dhcp-range=172.16.99.100,172.16.99.200,255.255.255.0,24h
dhcp-option=tag:eth1.99,option:router,172.16.99.1
dhcp-option=tag:eth1.99,option:dns-server,8.8.8.8
EOF
