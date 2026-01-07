KEYMAPOPTS="us us"
HOSTNAMEOPTS="-n cyberrange-router"
# Networking: eth0 DHCP, eth1 manual (để dành cho VLAN)
INTERFACESOPTS="auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp

auto eth1
iface eth1 inet manual
"

DNSOPTS="-d 8.8.8.8"
TIMEZONEOPTS="-z Asia/Ho_Chi_Minh"
PROXYOPTS="none"
APKREPOSOPTS="-1"

# --- KEY MAGIC: Inject Public Key trực tiếp ---
# openssh phải được cài đặt thì mới nhận key
SSHDOPTS="-o PermitRootLogin=prohibit-password"
ROOTSSHKEY="${ssh_public_key}"

# Disk & NTP
NTPOPTS="-c chrony"
DISKOPTS="-m sys /dev/vda"
LBUOPTS="none"
APKCACHEOPTS="/var/cache/apk"
