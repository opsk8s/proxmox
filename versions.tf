terraform {
  required_version = ">= 1.14.0" # provider-defined actions (action block) require Terraform 1.14+
  backend "local" {
    path = "./.state/terraform.tfstate"
  }
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.111.1"
    }
    ansible = {
      version = "~> 1.4.0"
      source  = "ansible/ansible"
    }
  }
}