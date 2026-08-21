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

variable "os_ssd_fast" {
  type = string
  default = "os-ssd-fast"
}

variable "os_ssd_slow" {
  type = string
  default = "os-ssd-slow"
}

variable "hf_token" {
  type = string
}