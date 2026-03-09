build {
  sources = ["source.proxmox-iso.alpine"]

  provisioner "shell" {
    script = "scripts/setup-network.sh"
  }
 
  provisioner "file" {
    source      = "scripts/qm-vlan.sh"
    destination = "/usr/local/bin/qm-vlan"
  }

  provisioner "file" {
    source      = "scripts/add-domain.sh"
    destination = "/usr/local/bin/add-domain"
  }

  provisioner "shell" {
    inline = [
      "chmod +x /usr/local/bin/qm-vlan",
      "chmod +x /usr/local/bin/add-domain",
      "echo 'Build Complete via SSH Key!'",
      "apk add curl iptables"
    ]
  }
}
