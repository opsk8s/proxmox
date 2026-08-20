terraform {
  backend "local" {
    path = "./.state/terraform.tfstate"
  }
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.111.1"
    }
  }
}