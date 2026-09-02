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

# --- LAN addressing (all in proxmox.tfvars) ----------------------------------
# Single /24 on vmbr0; every VM gets a static address. The playbooks receive
# these via the ansible_playbook_run extra_vars; the Makefile targets read the
# same values from $(TFVARS).

variable "lan_network" {
  type        = string
  description = "LAN network in CIDR notation, e.g. 192.168.51.0/24"
}

variable "lan_gateway" {
  type        = string
  description = "LAN default gateway (router) IP"
}

variable "pve_ip" {
  type        = string
  description = "PVE host IP"
}

variable "llm_ip" {
  type        = string
  description = "IP of the LLM inference VM"
}

variable "jenkins_ip" {
  type        = string
  description = "IP of the Jenkins controller VM"
}

variable "jenkins_agent_ip" {
  type        = string
  description = "IP of the Jenkins agent VM"
}

variable "open_webui_ip" {
  type        = string
  description = "IP of the Open WebUI VM"
}

variable "postgres_ip" {
  type        = string
  description = "IP of the PostgreSQL VM"
}

variable "monitoring_ip" {
  type        = string
  description = "IP of the monitoring (Prometheus/Grafana) VM"
}

variable "elk_ip" {
  type        = string
  description = "IP of the ELK (Elasticsearch/Kibana) VM"
}

variable "dns_ip" {
  type        = string
  description = "IP of the private DNS (dnsmasq) VM"
}

