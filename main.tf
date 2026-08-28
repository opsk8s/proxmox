provider "proxmox" {
  endpoint = "https://192.168.51.200:8006/"
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

  depends_on = [proxmox_download_file.fedora_cloud_image]
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

  depends_on = [proxmox_download_file.fedora_cloud_image]
}

module "jenkins_agent" {
  source               = "./modules/jenkins-agent"
  main_node            = var.main_node
  backup_dir           = var.backup_dir
  vm_dir               = var.vm_dir
  ubuntu_image_id      = proxmox_download_file.ubuntu_cloud_image.id
  ssh_public_key       = trimspace(data.local_file.jenkins_public_key.content)
  ssh_private_key_file = var.jenkins_agent_ssh_private_key_file

  depends_on = [proxmox_download_file.fedora_cloud_image]
}

module "open_webui" {
  source               = "./modules/open-webui"
  main_node            = var.main_node
  backup_dir           = var.backup_dir
  vm_dir               = var.vm_dir
  ubuntu_image_id      = proxmox_download_file.ubuntu_cloud_image.id
  ssh_public_key       = trimspace(data.local_file.public_key.content)
  ssh_private_key_file = var.ssh_private_key_file

  depends_on = [proxmox_download_file.fedora_cloud_image]
}

module "postgres" {
  source               = "./modules/postgres"
  main_node            = var.main_node
  backup_dir           = var.backup_dir
  vm_dir               = var.vm_dir
  ubuntu_image_id      = proxmox_download_file.ubuntu_cloud_image.id
  ssh_public_key       = trimspace(data.local_file.public_key.content)
  postgres_password    = var.postgres_password
  ssh_private_key_file = var.ssh_private_key_file

  depends_on = [proxmox_download_file.fedora_cloud_image]
}

#  zpool import -f os-ssd-fast
#  zpool import -f os-ssd-slow
#  zpool import -f backup-slow
#  pvesm add zfspool os-ssd-fast --pool os-ssd-fast
#  pvesm add zfspool os-ssd-slow --pool os-ssd-slow
#  pvesm add zfspool backup-slow --pool backup-slow
