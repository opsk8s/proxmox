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

# IP of every other VM — Prometheus scrape targets (playbook extra_vars)
variable "llm_ip" {
  type = string
}

variable "jenkins_ip" {
  type = string
}

variable "jenkins_agent_ip" {
  type = string
}

variable "open_webui_ip" {
  type = string
}

variable "postgres_ip" {
  type = string
}

variable "elk_ip" {
  type = string
}

variable "nginx_ip" {
  type = string
}

variable "taiga_ip" {
  type = string
}

variable "git_ip" {
  type = string
}

variable "qdrant_ip" {
  type = string
}

variable "langflow_ip" {
  type = string
}

variable "grafana_admin_password" {
  type = string
}

variable "jenkins_admin_password" {
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
