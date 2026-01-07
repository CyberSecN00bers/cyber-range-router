build {
  sources = ["source.proxmox-iso.alpine"]

  provisioner "shell" {
    script = "scripts/setup-network.sh"
  }
 
  provisioner "file" {
    source      = "scripts/qm-vlan.sh"
    destination = "/usr/local/bin/qm-vlan"
  }

  provisioner "shell" {
    inline = [
      "chmod +x /usr/local/bin/qm-vlan",
      "echo 'Build Complete via SSH Key!'",
      "apk add curl iptables"
    ]
  }
}
