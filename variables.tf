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

variable "taiga_db_password" {
  type        = string
  description = "Password for the taiga database user (see modules/postgres/database.yaml)"
}

variable "taiga_admin_password" {
  type        = string
  description = "Taiga admin (superuser) password, created on the first deploy run"
}

variable "grafana_admin_password" {
  type        = string
  description = "Grafana admin password"
}

variable "git_admin_password" {
  type        = string
  description = "Gitea admin (first user) password, created on the first deploy run"
}

variable "lan_ca_token" {
  type        = string
  description = "Shared token guarding the gateway's /lan-ca.pem endpoint (sent as the x-lan-ca-token header); the VM playbooks present it when fetching the CA root"
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

variable "taiga_ip" {
  type        = string
  description = "IP of the Taiga VM"
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

variable "nginx_ip" {
  type        = string
  description = "IP of the NGINX reverse proxy VM"
}

variable "git_ip" {
  type        = string
  description = "IP of the Gitea (git server) VM"
}

variable "keyboard_layout" {
  type        = string
  description = "Keyboard layout for the VM consoles (e.g. de-ch)"
}

# --- VM sizing (CPU cores / dedicated memory in MB) ----------------------------
variable "llm_cpu_cores" {
  type    = number
  default = 4
}

variable "llm_memory_mb" {
  type    = number
  default = 32768
}

variable "jenkins_cpu_cores" {
  type    = number
  default = 2
}

variable "jenkins_memory_mb" {
  type    = number
  default = 8192
}

variable "jenkins_agent_cpu_cores" {
  type    = number
  default = 4
}

variable "jenkins_agent_memory_mb" {
  type    = number
  default = 8192
}

variable "open_webui_cpu_cores" {
  type    = number
  default = 2
}

variable "open_webui_memory_mb" {
  type    = number
  default = 4096
}

variable "postgres_cpu_cores" {
  type    = number
  default = 8
}

variable "postgres_memory_mb" {
  type    = number
  default = 16384
}

variable "monitoring_cpu_cores" {
  type    = number
  default = 2
}

variable "monitoring_memory_mb" {
  type    = number
  default = 2048
}

variable "elk_cpu_cores" {
  type    = number
  default = 2
}

variable "elk_memory_mb" {
  type    = number
  default = 6144
}

variable "dns_cpu_cores" {
  type    = number
  default = 1
}

variable "dns_memory_mb" {
  type    = number
  default = 1024
}

variable "nginx_cpu_cores" {
  type    = number
  default = 2
}

variable "nginx_memory_mb" {
  type    = number
  default = 2048
}

variable "taiga_cpu_cores" {
  type    = number
  default = 2
}

variable "taiga_memory_mb" {
  type    = number
  default = 4096
}

variable "git_cpu_cores" {
  type    = number
  default = 1
}

variable "git_memory_mb" {
  type    = number
  default = 1024
}

