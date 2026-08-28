variable "main_node" {
  type    = string
  default = "pve"
}

variable "backup_dir" {
  type    = string
  default = "backup-slow-dir"
}

variable "vm_dir" {
  type    = string
  default = "local-lvm"
}

variable "os_ssd_fast" {
  type    = string
  default = "os-ssd-fast"
}

variable "os_ssd_slow" {
  type    = string
  default = "os-ssd-slow"
}

variable "ssh_private_key_file" {
  type        = string
  description = "Path to the SSH private key Ansible uses to connect to the VMs"
}

variable "jenkins_agent_ssh_private_key_file" {
  type        = string
  description = "Path to the SSH private key for the jenkins-agent VM (its cloud-init installs the jenkins-agent key, not the shared one)"
}

variable "hf_token" {
  type = string
}

variable "jenkins_admin_password" {
  type        = string
  description = "Jenkins admin password"
}

variable "jenkins_admin_email" {
  type        = string
  description = "admin email"
}

variable "postgres_password" {
  type        = string
  description = "PostgreSQL superuser password"
}

variable "grafana_admin_password" {
  type        = string
  description = "Grafana admin password"
}

variable "ct_template_file_id" {
  type        = string
  description = "File ID of an existing Ubuntu OS template (vztmpl) for the monitoring LXC, e.g. 'backup-slow-dir:vztmpl/ubuntu-26.04-....vztmpl'. List templates with 'pveam list' on the PVE host (or GUI: Datacenter -> Storage -> <store> -> Content -> Template OS)."
  validation {
    condition     = length(var.ct_template_file_id) > 0
    error_message = "Set ct_template_file_id in proxmox.tfvars to an existing vztmpl (find one with 'pveam list' on the PVE host). The Proxmox template mirror is subscription-gated, so it must already be on the server."
  }
}
