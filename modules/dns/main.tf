# Private DNS (dnsmasq) for the 192.168.51.0/24 LAN
#
# Small dedicated VM (1 core / 512MB / 10GB) that serves static .lan records
# for every VM in this repo and forwards everything else to public upstreams
# over DNS-over-TLS (Cloudflare / Quad9, port 853).
#
# The other VMs point at it via initialization.dns in their own modules
# (PVE cloud-init bakes that into their netplan on every boot); non-VM LAN
# devices get it via the router's DHCP DNS option (set it to 192.168.51.210).
#
# Endpoints once running (192.168.51.220:53): postgres.lan, grafana.lan,
# kibana.lan, jenkins.lan, open-webui.lan, elasticsearch.lan, ...
#
# WARNING: same cloud-init seed caveat as the other VMs —
# changing the snippet after creation forces a FULL VM recreation.

resource "proxmox_virtual_environment_file" "dns_config" {
  content_type = "snippets"
  datastore_id = var.backup_dir
  node_name    = var.main_node

  source_raw {
    data = templatefile("${path.module}/cloud-init.yaml", {
      dns_public_key = trimspace(var.ssh_public_key)
    })
    file_name = "dns-config.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "dns_vm" {
  name            = "dns"
  node_name       = var.main_node
  vm_id           = 220
  tags            = ["dns", "dnsmasq"]
  stop_on_destroy = true

  agent {
    enabled = true
  }

  initialization {
    # Own resolver goes straight to the router: dnsmasq on this VM must
    # never use itself as upstream.
    dns {
      domain  = "lan"
      servers = [var.lan_gateway]
    }

    ip_config {
      ipv4 {
        address = "${var.lan_ip}/${split("/", var.lan_network)[1]}"
        gateway = var.lan_gateway
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.dns_config.id
  }

  // 1 physical
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

  # first up so the rest of the LAN can resolve while the host boots
  startup {
    order = 1
  }

  depends_on = [
    proxmox_virtual_environment_file.dns_config
  ]

  lifecycle {
    action_trigger {
      events     = [after_create, after_update]
      actions    = [action.ansible_playbook_run.configure_dns]
      on_failure = halt
    }
  }
}

action "ansible_playbook_run" "configure_dns" {
  config {
    playbooks        = ["${path.module}/ansible.yml"]
    inventory_files  = ["${path.module}/inventory.ini"]
    private_key_file = var.ssh_private_key_file
    extra_vars = {
      ansible_host     = var.lan_ip
      pve_ip           = var.pve_ip
      dns_ip           = var.dns_ip
      llm_ip           = var.llm_ip
      jenkins_ip       = var.jenkins_ip
      jenkins_agent_ip = var.jenkins_agent_ip
      open_webui_ip    = var.open_webui_ip
      postgres_ip      = var.postgres_ip
      taiga_ip         = var.taiga_ip
      monitoring_ip    = var.monitoring_ip
      elk_ip           = var.elk_ip
      nginx_ip         = var.nginx_ip
      git_ip           = var.git_ip
      lan_gateway      = var.lan_gateway
    }
  }
}

output "dns_server" {
  value     = var.dns_ip
  sensitive = false
}
