# postgres vm
# WARNING: same cloud-init seed caveat as the jenkins VM above —
# changing the snippet after creation forces a FULL VM recreation.
resource "proxmox_virtual_environment_file" "postgres_config" {
  content_type = "snippets"
  datastore_id = var.backup_dir
  node_name    = var.main_node

  source_raw {
    data = templatefile("${path.module}/postgres-config.yaml", {
      postgres_public_key = trimspace(var.ssh_public_key)
    })
    file_name = "postgres-config.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "postgres_vm" {
  name            = "postgres"
  node_name       = var.main_node
  vm_id           = 104
  tags            = ["ubuntu", "postgres", "db"]
  stop_on_destroy = true

  agent {
    enabled = true
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.51.205/24"
        gateway = "192.168.51.1"
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.postgres_config.id
  }
  // 4 physical
  cpu {
    sockets = 1
    cores   = 8
  }

  memory {
    dedicated = 16384
  }

  disk {
    datastore_id = var.vm_dir
    file_id      = var.ubuntu_image_id
    interface    = "virtio0"
    size         = 50
    backup       = true
  }

  network_device {
    bridge = "vmbr0"
  }
  keyboard_layout = "de-ch"

  depends_on = [
    proxmox_virtual_environment_file.postgres_config
  ]
}

resource "null_resource" "configure_postgres" {
  triggers = {
    vm_id    = proxmox_virtual_environment_vm.postgres_vm.id
    playbook = filesha256("${path.module}/postgres.yml")
  }

  provisioner "local-exec" {
    command = "ansible-playbook -i ${path.module}/inventory.ini ${path.module}/postgres.yml"
    environment = {
      POSTGRES_PASSWORD = var.postgres_password
    }
  }

  depends_on = [
    proxmox_virtual_environment_vm.postgres_vm
  ]
}
