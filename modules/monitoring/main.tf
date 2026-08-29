# Monitoring stack (Prometheus + Grafana + blackbox_exporter)
#
# Runs in a dedicated VM (2 cores / 2GB / 10GB) so it does not steal
# physical cores from the LLM workload (the host is fully allocated).
#
# Endpoints once running (Grafana :3000, Prometheus :9090 on 192.168.51.206).
#
# WARNING: same cloud-init seed caveat as the other VMs —
# changing the snippet after creation forces a FULL VM recreation.

resource "proxmox_virtual_environment_file" "monitoring_config" {
  content_type = "snippets"
  datastore_id = var.backup_dir
  node_name    = var.main_node

  source_raw {
    data = templatefile("${path.module}/cloud-init.yaml", {
      monitoring_public_key = trimspace(var.ssh_public_key)
    })
    file_name = "monitoring-config.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "monitoring_vm" {
  name            = "monitoring"
  node_name       = var.main_node
  vm_id           = 200
  tags            = ["monitoring", "prometheus", "grafana"]
  stop_on_destroy = true

  agent {
    enabled = true
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.51.206/24"
        gateway = "192.168.51.1"
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.monitoring_config.id
  }

  // 2 physical
  cpu {
    sockets = 1
    cores   = 2
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = var.vm_dir
    file_id      = var.ubuntu_image_id
    interface    = "virtio0"
    size         = 10
    backup       = true
  }

  network_device {
    bridge = "vmbr0"
  }

  keyboard_layout = "de-ch"

  startup {
    order = 5
  }

  depends_on = [
    proxmox_virtual_environment_file.monitoring_config
  ]

  lifecycle {
    action_trigger {
      events     = [after_create, after_update]
      actions    = [action.ansible_playbook_run.configure_monitoring]
      on_failure = halt
    }
  }
}

action "ansible_playbook_run" "configure_monitoring" {
  config {
    playbooks        = ["${path.module}/ansible.yml"]
    inventory_files  = ["${path.module}/inventory.ini"]
    private_key_file = var.ssh_private_key_file
    extra_vars = {
      grafana_admin_password = var.grafana_admin_password
    }
  }
}

output "grafana_url" {
  value     = "http://192.168.51.206:3000"
  sensitive = false
}
