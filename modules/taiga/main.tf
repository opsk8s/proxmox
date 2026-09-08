# taiga vm
# WARNING: same cloud-init seed caveat as the jenkins VM above —
# changing the snippet after creation forces a FULL VM recreation.
resource "proxmox_virtual_environment_file" "taiga_config" {
  content_type = "snippets"
  datastore_id = var.backup_dir
  node_name    = var.main_node

  source_raw {
    data = templatefile("${path.module}/cloud-init.yaml", {
      taiga_public_key = trimspace(var.ssh_public_key)
    })
    file_name = "taiga-config.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "taiga_vm" {
  name            = "taiga"
  node_name       = var.main_node
  vm_id           = 105
  tags            = ["ubuntu", "taiga"]
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

    user_data_file_id = proxmox_virtual_environment_file.taiga_config.id
  }
  // one physical
  cpu {
    sockets = 1
    cores   = var.cpu_cores
  }

  memory {
    dedicated = var.memory_mb
  }

  disk {
    datastore_id = var.vm_dir
    file_id      = var.ubuntu_image_id
    interface    = "virtio0"
    size         = 20
    backup       = true
  }

  network_device {
    bridge = "vmbr0"
  }
  keyboard_layout = var.keyboard_layout

  depends_on = [
    proxmox_virtual_environment_file.taiga_config
  ]

  lifecycle {
    action_trigger {
      events     = [after_create, after_update]
      actions    = [action.ansible_playbook_run.configure_taiga]
      on_failure = halt
    }
  }
}

action "ansible_playbook_run" "configure_taiga" {
  config {
    playbooks        = ["${path.module}/ansible.yml"]
    inventory_files  = ["${path.module}/inventory.ini"]
    private_key_file = var.ssh_private_key_file
    extra_vars = {
      ansible_host         = var.lan_ip
      taiga_db_password    = var.taiga_db_password
      taiga_admin_password = var.taiga_admin_password
      postgres_ip          = var.postgres_ip
    }
  }
}
