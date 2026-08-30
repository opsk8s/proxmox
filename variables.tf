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

variable "smartshift_admin_password" {
  type        = string
  description = "Password for the smartshift_admin role (see modules/postgres/database.yaml)"
}

variable "analytics_ro_password" {
  type        = string
  description = "Password for the analytics_ro role (see modules/postgres/database.yaml)"
}

variable "grafana_admin_password" {
  type        = string
  description = "Grafana admin password"
}

