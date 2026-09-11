# used physical cores 4 + 1 + 2 + 1 + 4 = 12
# VM - llm
resource "proxmox_virtual_environment_file" "llm_config" {
  content_type = "snippets"
  datastore_id = var.backup_dir
  node_name    = var.main_node

  source_raw {
    data = templatefile("${path.module}/cloud-init.yaml", {
      llm_public_key = trimspace(var.ssh_public_key)
      hf_token       = var.hf_token
    })
    file_name = "llm-config.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "llm_vm" {
  name            = "llm-ubuntu"
  node_name       = var.main_node
  vm_id           = 100
  tags            = ["ubuntu", "llm", "rocm", "amd"]
  stop_on_destroy = true

  agent {
    enabled = true
  }

  initialization {
    # uncomment and specify the datastore for cloud-init disk if default `local-lvm` is not available
    # datastore_id = "local-lvm"

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

    user_data_file_id = proxmox_virtual_environment_file.llm_config.id
  }
  // 8 physical
  cpu {
    sockets = 1
    cores   = var.cpu_cores
    # the default qemu64 CPU exposes a baseline-only feature set (no SSE4.2/POPCNT)
    # and numpy 2.x / torch wheels refuse to load on it; pass the host's features
    # through so the Kokoro TTS stack (torch) can run.
    type = "host"
  }

  memory {
    dedicated = var.memory_mb
  }

  disk {
    datastore_id = var.vm_dir
    file_id      = var.ubuntu_image_id
    interface    = "virtio0"
    size         = 100
    backup       = true
  }

  # Second disk (additional storage)
  disk {
    datastore_id = var.os_ssd_fast # or use a different datastore
    interface    = "virtio1"
    size         = 500 # size in GB
    backup       = true
    # file_format = "raw"      # optional: specify format (raw, qcow2)
  }

  network_device {
    bridge = "vmbr0"
  }

  # GPU 1
  hostpci {
    device = "hostpci0"
    id     = "0000:03:00.0"
  }
  hostpci {
    device = "hostpci1"
    id     = "0000:03:00.1"
  }
  # GPU 2
  hostpci {
    device = "hostpci2"
    id     = "0000:2d:00.0"
  }
  hostpci {
    device = "hostpci3"
    id     = "0000:2d:00.1"
  }
  # GPU 3
  hostpci {
    device = "hostpci4"
    id     = "0000:43:00.0"
  }
  hostpci {
    device = "hostpci5"
    id     = "0000:43:00.1"
  }
  # GPU 4
  hostpci {
    device = "hostpci6"
    id     = "0000:63:00.0"
  }
  hostpci {
    device = "hostpci7"
    id     = "0000:63:00.1"
  }

  keyboard_layout = var.keyboard_layout

  depends_on = [
    proxmox_virtual_environment_file.llm_config
  ]

  lifecycle {
    action_trigger {
      events     = [after_create, after_update]
      actions    = [action.ansible_playbook_run.configure_llm]
      on_failure = halt
    }
  }
}


# AMD GPU profiles (-P COMPUTE, -l HIGH) are applied on every boot by
# amd-gpu-profile.service (deployed by ansible.yml, ordered before the
# llama-server units) — no manual action needed.
# Manual power cap (not applied on boot): sudo amd-smi set -o 300
action "ansible_playbook_run" "configure_llm" {
  config {
    playbooks        = ["${path.module}/ansible.yml"]
    inventory_files  = ["${path.module}/inventory.ini"]
    private_key_file = var.ssh_private_key_file
    extra_vars = {
      ansible_host = var.lan_ip
    }
  }
}
