source "proxmox-iso" "alpine" {
  # Proxmox Auth
  proxmox_url               = var.proxmox_url
  username                  = var.proxmox_username
  token                     = var.proxmox_token
  node                      = var.proxmox_node
  insecure_skip_tls_verify  = true
  
  # ISO
  boot_iso {
    type             = "scsi"
    iso_url          = "https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/x86_64/alpine-virt-3.23.2-x86_64.iso"
    iso_checksum     = "file:https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/x86_64/alpine-virt-3.23.2-x86_64.iso.sha256"
    iso_storage_pool = "local"
    # iso_download_pve = true
    unmount          = true
  }

  # VM Specs
  vm_name         = "cyberrange-router"
  template_name   = "cyberrange-router"
  memory          = 512
  sockets         = 1
  cores           = 1
  scsi_controller = "virtio-scsi-single"
  qemu_agent      = true

  template_description = "Alpine Router"
  tags                 = "alpine;router"

  
  # Network: 2 Cards (WAN/LAN)
  network_adapters {
    model  = "virtio"
    bridge = var.bridge_wan
    firewall = false
  }
  network_adapters {
    model  = "virtio"
    bridge = var.bridge_lan
    firewall = false
  }

  disks {
    type         = "scsi"
    disk_size    = "4G"
    storage_pool = "local-lvm"
    format       = "raw"
  }

  # --- HTTP Server: Serve Answer File Dynamic ---
  http_content = {
    "/answers" = templatefile("http/answers.pkrtpl.hcl", {
      ssh_public_key = var.ssh_public_key
    })
  }

  # Boot Command
  boot_wait = "10s"
  boot_command = [
    "<enter><wait>",
    "root<enter><wait>",
    "ifconfig eth0 up && udhcpc -i eth0<enter><wait5>",
    "wget -O /tmp/answers http://{{ .HTTPIP }}:{{ .HTTPPort }}/answers<enter><wait>",

    "ERASE_DISKS=/dev/sda setup-alpine -e -f /tmp/answers && mount /dev/sda3 /mnt && apk add --root /mnt qemu-guest-agent && chroot /mnt rc-update add qemu-guest-agent default && reboot<enter>"
  ]

  # --- SSH Communicator (KEY ONLY) ---
  vm_interface         = "eth0"
  ssh_username         = "root"
  ssh_private_key_file = var.ssh_private_key_file
  ssh_timeout          = "20m"

  # Cloud-init
  cloud_init              = true
  cloud_init_storage_pool = "local-lvm"
}

