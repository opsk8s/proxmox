# OpenSearch stack (OpenSearch + Dashboards) for LLM request-plane
# observability. Replaced Elasticsearch 9 + Kibana 9 in place (VM 201, 2026-09):
# same ports, same Filebeat shippers, same ILM/pipeline semantics.
#
# Receives Filebeat-shipped logs from the LLM VM (llama-server slot/timing
# events) into the `llm-logs-*` daily indices.
#
# Sizing note: the host is fully allocated (12 cores, ~70GB RAM in use).
# 2 cores / 6GB is the floor for OpenSearch + Dashboards. Free RAM on
# the host before the first apply if the allocation total exceeds it.
#
# Endpoints once running (Dashboards :5601, OpenSearch :9200 on 192.168.51.207).
# Security is DISABLED (plugins.security.disabled=true): consistent with the
# rest of the lab (Prometheus, node_exporter, llama /metrics are all
# unauthenticated on the trusted LAN). Re-enable before exposing beyond 192.168.51.0/24.
#
# WARNING: same cloud-init seed caveat as the other VMs —
# changing the snippet after creation forces a FULL VM recreation.

resource "proxmox_virtual_environment_file" "elk_config" {
  content_type = "snippets"
  datastore_id = var.backup_dir
  node_name    = var.main_node

  source_raw {
    data = templatefile("${path.module}/cloud-init.yaml", {
      elk_public_key = trimspace(var.ssh_public_key)
    })
    file_name = "elk-config.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "elk_vm" {
  name            = "elk"
  node_name       = var.main_node
  vm_id           = 201
  tags            = ["elk", "opensearch", "dashboards"]
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

    user_data_file_id = proxmox_virtual_environment_file.elk_config.id
  }

  // 2 physical (lab is core-saturated; OpenSearch+Dashboards are idle-most-of-the-time)
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
    size         = 30
    backup       = true
  }

  network_device {
    bridge = "vmbr0"
  }

  keyboard_layout = var.keyboard_layout

  startup {
    order = 5
  }

  depends_on = [
    proxmox_virtual_environment_file.elk_config
  ]

  lifecycle {
    action_trigger {
      events     = [after_create, after_update]
      actions    = [action.ansible_playbook_run.configure_elk]
      on_failure = halt
    }
  }
}

action "ansible_playbook_run" "configure_elk" {
  config {
    playbooks        = ["${path.module}/ansible.yml"]
    inventory_files  = ["${path.module}/inventory.ini"]
    private_key_file = var.ssh_private_key_file
    extra_vars = {
      ansible_host = var.lan_ip
      es_ip        = var.lan_ip
    }
  }
}

output "dashboards_url" {
  value     = "http://${var.lan_ip}:5601"
  sensitive = false
}
