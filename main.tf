provider "proxmox" {
  endpoint = "https://192.168.51.200:8006/"
  username = "root@pam"
  # because self-signed TLS certificate is in use
  insecure = true
}


data "proxmox_version" "pve" {}

output "data_proxmox_version" {
  value = {
    release       = data.proxmox_version.pve.release
    repository_id = data.proxmox_version.pve.repository_id
    version       = data.proxmox_version.pve.version
  }
}

data "local_file" "public_key" {
  filename = "/Users/ffhs/.ssh/proxmox-ubuntu.pub"
}

