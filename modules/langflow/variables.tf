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

# nginx gateway: the CA root is fetched from it and app.langflow.lan is
# served by it (the VM playbook only talks to the gateway, never to the
# individual backends).
variable "nginx_ip" {
  type = string
}

# Langflow stores flows/credentials in an external Postgres database
# (role + database provisioned by modules/postgres, see database.yaml).
variable "postgres_ip" {
  type = string
}

variable "langflow_db_password" {
  type = string
}

# Optional in Langflow itself (unset = auto-generated), but pinned here:
# the key signs JWTs and encrypts stored credentials, so losing it would
# orphan them.
variable "langflow_superuser_password" {
  type = string
}

# Vector store access (Qdrant REST API key); exposed to flows as the
# QDRANT_API_KEY global variable.
variable "qdrant_api_key" {
  type      = string
  sensitive = true
}

variable "lan_ca_token" {
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
