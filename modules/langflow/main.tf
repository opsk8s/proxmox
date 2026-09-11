# langflow vm
# WARNING: same cloud-init seed caveat as the jenkins VM above —
# changing the snippet after creation forces a FULL VM recreation.
resource "proxmox_virtual_environment_file" "langflow_config" {
  content_type = "snippets"
  datastore_id = var.backup_dir
  node_name    = var.main_node

  source_raw {
    data = templatefile("${path.module}/cloud-init.yaml", {
      langflow_public_key = trimspace(var.ssh_public_key)
    })
    file_name = "langflow-config.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "langflow_vm" {
  name            = "langflow"
  node_name       = var.main_node
  vm_id           = 108
  tags            = ["ubuntu", "langflow", "ai"]
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

    user_data_file_id = proxmox_virtual_environment_file.langflow_config.id
  }
  // two physical
  cpu {
    sockets = 1
    cores   = var.cpu_cores
    # the default qemu64 CPU exposes a baseline-only feature set (no SSE4.2/POPCNT)
    # and the numpy/torch wheels Langflow pulls in refuse to load on it; pass the
    # host's features through (same fix as the open-webui VM)
    type = "host"
  }

  memory {
    dedicated = var.memory_mb
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

  # after dns (name resolution), postgres (flows/credentials database) and
  # nginx (the langflow VM fetches the LAN CA root from it and the service is
  # reached through app.langflow.lan)
  startup {
    order = 7
  }

  depends_on = [
    proxmox_virtual_environment_file.langflow_config
  ]

  lifecycle {
    action_trigger {
      events     = [after_create, after_update]
      actions    = [action.ansible_playbook_run.configure_langflow]
      on_failure = halt
    }
  }
}

action "ansible_playbook_run" "configure_langflow" {
  config {
    playbooks        = ["${path.module}/ansible.yml"]
    inventory_files  = ["${path.module}/inventory.ini"]
    private_key_file = var.ssh_private_key_file
    extra_vars = {
      ansible_host                = var.lan_ip
      langflow_ip                 = var.lan_ip
      nginx_ip                    = var.nginx_ip
      postgres_ip                 = var.postgres_ip
      qdrant_api_key              = var.qdrant_api_key
      lan_ca_token                = var.lan_ca_token
      langflow_superuser_password = var.langflow_superuser_password
      langflow_db_password        = var.langflow_db_password
    }
  }
}

output "langflow_url" {
  value     = "https://app.langflow.lan"
  sensitive = false
}
