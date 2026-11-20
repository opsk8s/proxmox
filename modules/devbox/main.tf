resource "proxmox_virtual_environment_file" "devbox_config" {
  content_type = "snippets"
  datastore_id = var.backup_dir
  node_name    = var.main_node

  source_raw {
    data = templatefile("${path.module}/cloud-init.yaml", {
      devbox_public_key = trimspace(var.ssh_public_key)
    })
    file_name = "devbox-config.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "devbox_vm" {
  name            = "devbox"
  node_name       = var.main_node
  vm_id           = 109
  tags            = ["ubuntu", "devbox", "dev"]
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
    user_data_file_id = proxmox_virtual_environment_file.devbox_config.id
  }

  # host-passthrough CPU features: the dev box compiles native code locally
  # (C/C++, Rust), and -cpu qemu64 lacks SSE4.2/POPCNT — same fix as the
  # llm VM. The 16-core default is sized for parallel builds (cargo make -j).
  cpu {
    sockets = 1
    cores   = var.cpu_cores
    type    = "host"
  }

  memory {
    dedicated = var.memory_mb
  }

  # 64 GB: toolchains + build artifacts (target dirs, node_modules, uv cache)
  # grow quickly; 32 GB is the size the other single-purpose VMs use.
  disk {
    datastore_id = var.vm_dir
    file_id      = var.ubuntu_image_id
    interface    = "virtio0"
    size         = 64
    backup       = true
  }

  network_device {
    bridge = "vmbr0"
  }

  keyboard_layout = var.keyboard_layout

  depends_on = [
    proxmox_virtual_environment_file.devbox_config,
  ]

  lifecycle {
    action_trigger {
      events  = [after_create, after_update]
      actions = [action.ansible_playbook_run.configure_devbox]
      on_failure = halt
    }
  }
}

# Toolchain install (C/C++, Rust, uv/Python, nvm/Node) — SSH-only, no public
# endpoint, so there is no nginx vhost to manage for this VM.
action "ansible_playbook_run" "configure_devbox" {
  config {
    playbooks       = ["${path.module}/ansible.yml"]
    inventory_files = ["${path.module}/inventory.ini"]
    private_key_file = var.ssh_private_key_file
    extra_vars = {
      ansible_host = var.lan_ip
    }
  }
}
