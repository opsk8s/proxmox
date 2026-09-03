# open-webui vm
# WARNING: same cloud-init seed caveat as the jenkins VM above —
# changing the snippet after creation forces a FULL VM recreation.
resource "proxmox_virtual_environment_file" "openwebui_config" {
  content_type = "snippets"
  datastore_id = var.backup_dir
  node_name    = var.main_node

  source_raw {
    data = templatefile("${path.module}/cloud-init.yaml", {
      openwebui_public_key = trimspace(var.ssh_public_key)
    })
    file_name = "openwebui-config.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "openwebui_vm" {
  name            = "open-webui"
  node_name       = var.main_node
  vm_id           = 103
  tags            = ["ubuntu", "webui", "llm"]
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

    user_data_file_id = proxmox_virtual_environment_file.openwebui_config.id
  }
  // one physical
  cpu {
    sockets = 1
    cores   = 2
    # the default qemu64 CPU exposes a baseline-only feature set (no SSE4.2/POPCNT)
    # and numpy 2.x wheels refuse to load on it; pass the host's features through
    type = "host"
  }

  memory {
    dedicated = 4096
  }

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
    proxmox_virtual_environment_file.openwebui_config
  ]

  lifecycle {
    action_trigger {
      events     = [after_create, after_update]
      actions    = [action.ansible_playbook_run.configure_openwebui]
      on_failure = halt
    }
  }
}

action "ansible_playbook_run" "configure_openwebui" {
  config {
    playbooks        = ["${path.module}/ansible.yml"]
    inventory_files  = ["${path.module}/inventory.ini"]
    private_key_file = var.ssh_private_key_file
    extra_vars = {
      ansible_host = var.lan_ip
      webui_ip     = var.lan_ip
      llm_ip       = var.llm_ip
    }
  }
}
