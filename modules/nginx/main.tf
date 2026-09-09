# Reverse proxy for every service in this repo.
#
# One virtual host per service (app.kibana.lan, app.grafana.lan, ...), each
# logging to a JSON access log (log_format json_analytics) that Filebeat on
# this VM ships to Elasticsearch (indices nginx-access-*, dashboards in the
# ELK and monitoring modules).
#
# WARNING: same cloud-init seed caveat as the other VMs —
# changing the snippet after creation forces a FULL VM recreation.

resource "proxmox_virtual_environment_file" "nginx_config" {
  content_type = "snippets"
  datastore_id = var.backup_dir
  node_name    = var.main_node

  source_raw {
    data = templatefile("${path.module}/cloud-init.yaml", {
      nginx_public_key = trimspace(var.ssh_public_key)
    })
    file_name = "nginx-config.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "nginx_vm" {
  name            = "nginx"
  node_name       = var.main_node
  vm_id           = 202
  tags            = ["nginx", "proxy"]
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

    user_data_file_id = proxmox_virtual_environment_file.nginx_config.id
  }

  // 2 physical
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
    size         = 10
    backup       = true
  }

  network_device {
    bridge = "vmbr0"
  }

  keyboard_layout = var.keyboard_layout

  startup {
    order = 6
  }

  depends_on = [
    proxmox_virtual_environment_file.nginx_config
  ]

  lifecycle {
    action_trigger {
      events     = [after_create, after_update]
      actions    = [action.ansible_playbook_run.configure_nginx]
      on_failure = halt
    }
  }
}

action "ansible_playbook_run" "configure_nginx" {
  config {
    playbooks        = ["${path.module}/ansible.yml"]
    inventory_files  = ["${path.module}/inventory.ini"]
    private_key_file = var.ssh_private_key_file
    extra_vars = {
      ansible_host  = var.lan_ip
      elk_ip        = var.elk_ip
      monitoring_ip = var.monitoring_ip
      jenkins_ip    = var.jenkins_ip
      open_webui_ip = var.open_webui_ip
      llm_ip        = var.llm_ip
      taiga_ip      = var.taiga_ip
      git_ip        = var.git_ip
      qdrant_ip     = var.qdrant_ip
      lan_ca_token  = var.lan_ca_token
    }
  }
}

output "nginx_url" {
  value     = "http://${var.lan_ip}"
  sensitive = false
}
