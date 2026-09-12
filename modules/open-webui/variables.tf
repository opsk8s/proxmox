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

variable "llm_ip" {
  type = string
}

# RAG vector store access (Qdrant REST API key) — Open WebUI stores and
# queries document embeddings in the qdrant VM.
variable "qdrant_api_key" {
  type      = string
  sensitive = true
}

variable "nginx_ip" {
  type = string
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
