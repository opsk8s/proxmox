variable "main_node" {
  type = string
  default = "pve"
}

variable "backup_dir" {
  type = string
  default = "backup-slow-dir"
}

variable "vm_dir" {
  type = string
  default = "local-lvm"
}

variable "hf_token" {
  type = string
}