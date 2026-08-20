resource "proxmox_download_file" "ubuntu_cloud_image" {
  content_type = "iso"
  datastore_id = var.backup_dir
  node_name    = var.main_node

  file_name = "ubuntu-26-04-lts.img"
  url       = "https://cloud-images.ubuntu.com/resolute/current/resolute-server-cloudimg-amd64.img"
}


resource "proxmox_download_file" "fedora_cloud_image" {
  content_type = "import"
  datastore_id = var.backup_dir
  node_name    = var.main_node
  file_name = "fedora-server-44.qcow2"
  url = "https://download.fedoraproject.org/pub/fedora/linux/releases/44/Server/x86_64/images/Fedora-Server-Guest-Generic-44-1.7.x86_64.qcow2"
}
