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

# Database on the shared postgres VM (provisioned by modules/postgres)
variable "taiga_db_password" {
  type = string
}

variable "postgres_ip" {
  type = string
}

# Admin login created on the first run
variable "taiga_admin_password" {
  type = string
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
