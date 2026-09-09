variable "main_node" {
  type = string
}

variable "backup_dir" {
  type = string
}

variable "vm_dir" {
  type = string
}

variable "ubuntu_image_id" {
  type = string
}

variable "ssh_public_key" {
  type = string
}

variable "ssh_private_key_file" {
  type = string
}

variable "lan_ip" {
  type = string
}

variable "lan_network" {
  type = string
}

variable "lan_gateway" {
  type = string
}

variable "dns_ip" {
  type = string
}

# Single API key required for every REST/gRPC call; the web UI prompts for
# it in the browser. Generated once in proxmox.tfvars.
variable "qdrant_api_key" {
  type        = string
  sensitive   = true
  description = "Qdrant service API key, passed to the unit as QDRANT__SERVICE__API_KEY"
}

variable "keyboard_layout" {
  type = string
}

variable "cpu_cores" {
  type = number
}

variable "memory_mb" {
  type = number
}
