provider "proxmox" {
  endpoint = "https://${var.pve_ip}:8006/"
  username = "root@pam"
  # because self-signed TLS certificate is in use
  insecure = true
}


data "proxmox_version" "pve" {}

output "data_proxmox_version" {
  value = {
    release       = data.proxmox_version.pve.release
    repository_id = data.proxmox_version.pve.repository_id
    version       = data.proxmox_version.pve.version
  }
}

data "local_file" "public_key" {
  filename = "/Users/ffhs/.ssh/proxmox-ubuntu.pub"
}

data "local_file" "jenkins_public_key" {
  filename = "/Users/ffhs/.ssh/jenkins-agent.pub"
}

module "llm" {
  source               = "./modules/llm"
  main_node            = var.main_node
  backup_dir           = var.backup_dir
  vm_dir               = var.vm_dir
  os_ssd_fast          = var.os_ssd_fast
  ubuntu_image_id      = proxmox_download_file.ubuntu_cloud_image.id
  ssh_public_key       = trimspace(data.local_file.public_key.content)
  hf_token             = var.hf_token
  ssh_private_key_file = var.ssh_private_key_file
  cpu_cores            = var.llm_cpu_cores
  memory_mb            = var.llm_memory_mb
  lan_ip               = var.llm_ip
  lan_network          = var.lan_network
  lan_gateway          = var.lan_gateway
  dns_ip               = var.dns_ip
  keyboard_layout      = var.keyboard_layout

  depends_on = [module.dns, proxmox_download_file.fedora_cloud_image]
}

module "jenkins" {
  source                 = "./modules/jenkins"
  main_node              = var.main_node
  backup_dir             = var.backup_dir
  vm_dir                 = var.vm_dir
  ubuntu_image_id        = proxmox_download_file.ubuntu_cloud_image.id
  ssh_public_key         = trimspace(data.local_file.public_key.content)
  jenkins_admin_password = var.jenkins_admin_password
  ssh_private_key_file   = var.ssh_private_key_file
  cpu_cores              = var.jenkins_cpu_cores
  memory_mb              = var.jenkins_memory_mb
  lan_ip                 = var.jenkins_ip
  lan_network            = var.lan_network
  lan_gateway            = var.lan_gateway
  dns_ip                 = var.dns_ip
  jenkins_agent_ip       = var.jenkins_agent_ip
  keyboard_layout        = var.keyboard_layout

  depends_on = [module.dns, proxmox_download_file.fedora_cloud_image]
}

module "jenkins_agent" {
  source               = "./modules/jenkins-agent"
  main_node            = var.main_node
  backup_dir           = var.backup_dir
  vm_dir               = var.vm_dir
  ubuntu_image_id      = proxmox_download_file.ubuntu_cloud_image.id
  ssh_public_key       = trimspace(data.local_file.jenkins_public_key.content)
  ssh_private_key_file = var.jenkins_agent_ssh_private_key_file
  cpu_cores            = var.jenkins_agent_cpu_cores
  memory_mb            = var.jenkins_agent_memory_mb
  lan_ip               = var.jenkins_agent_ip
  lan_network          = var.lan_network
  lan_gateway          = var.lan_gateway
  dns_ip               = var.dns_ip
  keyboard_layout      = var.keyboard_layout

  depends_on = [module.dns, proxmox_download_file.fedora_cloud_image]
}

module "open_webui" {
  source               = "./modules/open-webui"
  main_node            = var.main_node
  backup_dir           = var.backup_dir
  vm_dir               = var.vm_dir
  ubuntu_image_id      = proxmox_download_file.ubuntu_cloud_image.id
  ssh_public_key       = trimspace(data.local_file.public_key.content)
  ssh_private_key_file = var.ssh_private_key_file
  cpu_cores            = var.open_webui_cpu_cores
  memory_mb            = var.open_webui_memory_mb
  lan_ip               = var.open_webui_ip
  lan_network          = var.lan_network
  lan_gateway          = var.lan_gateway
  dns_ip               = var.dns_ip
  llm_ip               = var.llm_ip
  nginx_ip             = var.nginx_ip
  lan_ca_token         = var.lan_ca_token
  keyboard_layout      = var.keyboard_layout

  depends_on = [module.dns, proxmox_download_file.fedora_cloud_image]
}

module "postgres" {
  source                    = "./modules/postgres"
  main_node                 = var.main_node
  backup_dir                = var.backup_dir
  vm_dir                    = var.vm_dir
  ubuntu_image_id           = proxmox_download_file.ubuntu_cloud_image.id
  ssh_public_key            = trimspace(data.local_file.public_key.content)
  postgres_password         = var.postgres_password
  smartshift_admin_password = var.smartshift_admin_password
  analytics_ro_password     = var.analytics_ro_password
  taiga_db_password         = var.taiga_db_password
  ssh_private_key_file      = var.ssh_private_key_file
  cpu_cores                 = var.postgres_cpu_cores
  memory_mb                 = var.postgres_memory_mb
  lan_ip                    = var.postgres_ip
  lan_network               = var.lan_network
  lan_gateway               = var.lan_gateway
  dns_ip                    = var.dns_ip
  keyboard_layout           = var.keyboard_layout

  depends_on = [module.dns, proxmox_download_file.fedora_cloud_image]
}

module "taiga" {
  source               = "./modules/taiga"
  main_node            = var.main_node
  backup_dir           = var.backup_dir
  vm_dir               = var.vm_dir
  ubuntu_image_id      = proxmox_download_file.ubuntu_cloud_image.id
  ssh_public_key       = trimspace(data.local_file.public_key.content)
  ssh_private_key_file = var.ssh_private_key_file
  cpu_cores            = var.taiga_cpu_cores
  memory_mb            = var.taiga_memory_mb
  lan_ip               = var.taiga_ip
  lan_network          = var.lan_network
  lan_gateway          = var.lan_gateway
  dns_ip               = var.dns_ip
  taiga_db_password    = var.taiga_db_password
  taiga_admin_password = var.taiga_admin_password
  postgres_ip          = var.postgres_ip
  keyboard_layout      = var.keyboard_layout

  depends_on = [module.dns, module.postgres, proxmox_download_file.fedora_cloud_image]
}

module "monitoring" {
  source                 = "./modules/monitoring"
  main_node              = var.main_node
  backup_dir             = var.backup_dir
  vm_dir                 = var.vm_dir
  ubuntu_image_id        = proxmox_download_file.ubuntu_cloud_image.id
  ssh_public_key         = trimspace(data.local_file.public_key.content)
  grafana_admin_password = var.grafana_admin_password
  ssh_private_key_file   = var.ssh_private_key_file
  cpu_cores              = var.monitoring_cpu_cores
  memory_mb              = var.monitoring_memory_mb
  lan_ip                 = var.monitoring_ip
  lan_network            = var.lan_network
  lan_gateway            = var.lan_gateway
  dns_ip                 = var.dns_ip
  llm_ip                 = var.llm_ip
  jenkins_ip             = var.jenkins_ip
  jenkins_admin_password = var.jenkins_admin_password
  jenkins_agent_ip       = var.jenkins_agent_ip
  open_webui_ip          = var.open_webui_ip
  postgres_ip            = var.postgres_ip
  elk_ip                 = var.elk_ip
  nginx_ip               = var.nginx_ip
  taiga_ip               = var.taiga_ip
  keyboard_layout        = var.keyboard_layout

  depends_on = [module.dns, proxmox_download_file.fedora_cloud_image]
}

module "elk" {
  source               = "./modules/elk"
  main_node            = var.main_node
  backup_dir           = var.backup_dir
  vm_dir               = var.vm_dir
  ubuntu_image_id      = proxmox_download_file.ubuntu_cloud_image.id
  ssh_public_key       = trimspace(data.local_file.public_key.content)
  ssh_private_key_file = var.ssh_private_key_file
  cpu_cores            = var.elk_cpu_cores
  memory_mb            = var.elk_memory_mb
  lan_ip               = var.elk_ip
  lan_network          = var.lan_network
  lan_gateway          = var.lan_gateway
  dns_ip               = var.dns_ip
  keyboard_layout      = var.keyboard_layout

  depends_on = [module.dns, proxmox_download_file.fedora_cloud_image]
}

module "dns" {
  source               = "./modules/dns"
  main_node            = var.main_node
  backup_dir           = var.backup_dir
  vm_dir               = var.vm_dir
  ubuntu_image_id      = proxmox_download_file.ubuntu_cloud_image.id
  ssh_public_key       = trimspace(data.local_file.public_key.content)
  ssh_private_key_file = var.ssh_private_key_file
  cpu_cores            = var.dns_cpu_cores
  memory_mb            = var.dns_memory_mb
  lan_ip               = var.dns_ip
  lan_network          = var.lan_network
  lan_gateway          = var.lan_gateway
  dns_ip               = var.dns_ip
  pve_ip               = var.pve_ip
  llm_ip               = var.llm_ip
  jenkins_ip           = var.jenkins_ip
  jenkins_agent_ip     = var.jenkins_agent_ip
  open_webui_ip        = var.open_webui_ip
  postgres_ip          = var.postgres_ip
  taiga_ip             = var.taiga_ip
  monitoring_ip        = var.monitoring_ip
  elk_ip               = var.elk_ip
  nginx_ip             = var.nginx_ip
  keyboard_layout      = var.keyboard_layout

  depends_on = [proxmox_download_file.fedora_cloud_image]
}

module "nginx" {
  source               = "./modules/nginx"
  main_node            = var.main_node
  backup_dir           = var.backup_dir
  vm_dir               = var.vm_dir
  ubuntu_image_id      = proxmox_download_file.ubuntu_cloud_image.id
  ssh_public_key       = trimspace(data.local_file.public_key.content)
  ssh_private_key_file = var.ssh_private_key_file
  cpu_cores            = var.nginx_cpu_cores
  memory_mb            = var.nginx_memory_mb
  lan_ip               = var.nginx_ip
  lan_network          = var.lan_network
  lan_gateway          = var.lan_gateway
  dns_ip               = var.dns_ip
  elk_ip               = var.elk_ip
  monitoring_ip        = var.monitoring_ip
  jenkins_ip           = var.jenkins_ip
  open_webui_ip        = var.open_webui_ip
  llm_ip               = var.llm_ip
  taiga_ip             = var.taiga_ip
  lan_ca_token         = var.lan_ca_token
  keyboard_layout      = var.keyboard_layout

  depends_on = [module.dns, proxmox_download_file.fedora_cloud_image]
}

#  zpool import -f os-ssd-fast
#  zpool import -f os-ssd-slow
#  zpool import -f backup-slow
#  pvesm add zfspool os-ssd-fast --pool os-ssd-fast
#  pvesm add zfspool os-ssd-slow --pool os-ssd-slow
#  pvesm add zfspool backup-slow --pool backup-slow
