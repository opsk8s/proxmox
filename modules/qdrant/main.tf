# qdrant (vector database) vm
# WARNING: same cloud-init seed caveat as other modules —
# changing the snippet after creation forces a FULL VM recreation.
resource "proxmox_virtual_environment_file" "qdrant_config" {
  content_type = "snippets"
  datastore_id = var.backup_dir
  node_name    = var.main_node

  source_raw {
    data = templatefile("${path.module}/cloud-init.yaml", {
      qdrant_public_key = trimspace(var.ssh_public_key)
    })
    file_name = "qdrant-config.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "qdrant_vm" {
  name            = "qdrant"
  node_name       = var.main_node
  vm_id           = 107
  tags            = ["ubuntu", "qdrant"]
  stop_on_destroy = true

  agent {
    enabled = true
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${var.lan_ip}/${split("/", var.lan_network)[1]}"
        gateway = var.lan_gateway
      }
    }

    dns {
      domain  = "lan"
      servers = [var.dns_ip, var.lan_gateway]
    }

    user_data_file_id = proxmox_virtual_environment_file.qdrant_config.id
  }

  cpu {
    sockets = 1
    cores   = var.cpu_cores
    type    = "host"
  }

  memory {
    dedicated = var.memory_mb
  }

  # 32 GB like the git VM: storage lives on the VM disk (covered by PVE
  # backups via backup = true), vector collections are RAM-resident and
  # spill to this disk.
  disk {
    datastore_id = var.vm_dir
    file_id      = var.ubuntu_image_id
    interface    = "virtio0"
    size         = 32
    backup       = true
  }

  network_device {
    bridge = "vmbr0"
  }

  keyboard_layout = var.keyboard_layout

  depends_on = [
    proxmox_virtual_environment_file.qdrant_config
  ]

  lifecycle {
    action_trigger {
      events     = [after_create, after_update]
      actions    = [action.ansible_playbook_run.configure_qdrant]
      on_failure = halt
    }
  }
}

action "ansible_playbook_run" "configure_qdrant" {
  config {
    playbooks        = ["${path.module}/ansible.yml"]
    inventory_files  = ["${path.module}/inventory.ini"]
    private_key_file = var.ssh_private_key_file
    extra_vars = {
      ansible_host   = var.lan_ip
      qdrant_ip      = var.lan_ip
      qdrant_api_key = var.qdrant_api_key
    }
  }
}
