build {
  sources = ["source.proxmox-iso.alpine"]

  provisioner "shell" {
    script = "scripts/setup-network.sh"
  }
  
  provisioner "shell" {
    inline = [
      "echo 'Build Complete via SSH Key!'",
      "apk add curl iptables"
    ]
  }
}
