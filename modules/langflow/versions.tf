terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.111.1"
    }
    ansible = {
      source  = "ansible/ansible"
      version = "~> 1.4.0"
    }
  }
}
