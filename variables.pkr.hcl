variable "proxmox_url" {
  type = string
  default = "https://192.168.1.100:8006/api2/json"
}

variable "proxmox_username" {
  type = string
  default = "root@pam"
}

variable "proxmox_token" {
  type      = string
  sensitive = true
}

variable "proxmox_node" {
  type    = string
  default = "pve"
}

# --- SSH Key Config ---
variable "ssh_public_key" {
  description = "Nội dung Public Key (để đưa vào máy ảo)"
  type        = string
  # Ví dụ: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI..."
}

variable "ssh_private_key_file" {
  description = "Đường dẫn tới file Private Key (để Packer dùng SSH vào)"
  type        = string
  default     = "~/.ssh/id_ed25519"
}

# --- Network Config ---
variable "bridge_wan" {
  type    = string
  default = "vmbr0"
}

variable "bridge_lan" {
  type    = string
  default = "vmbr1"
}
