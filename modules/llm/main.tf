# used physical cores 4 + 1 + 2 + 1 + 4 = 12
# VM - llm
resource "proxmox_virtual_environment_file" "llm_config" {
  content_type = "snippets"
  datastore_id = var.backup_dir
  node_name    = var.main_node

  source_raw {
    data = templatefile("${path.module}/llm-config.yaml", {
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
        address = "192.168.51.201/24"
        gateway = "192.168.51.1"
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.llm_config.id
  }
  // 8 physical
  cpu {
    sockets = 1
    cores   = 8
  }

  memory {
    dedicated = 65536
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
    import_from  = ""
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

  keyboard_layout = "de-ch"

  depends_on = [
    proxmox_virtual_environment_file.llm_config
  ]
}


# AMD
# sudo amd-smi set -g 0 1 2 3 -P COMPUTE
# sudo amd-smi set -o 300
# sudo amd-smi set -g 0 1 2 3 -l HIGH
resource "null_resource" "configure_llm" {
  triggers = {
    vm_id    = proxmox_virtual_environment_vm.llm_vm.id
    playbook = filesha256("${path.module}/llm.yml")
    files = sha256(join("", [
      for file in fileset("${path.module}/llm-scripts", "*") :
      "${file}:${filesha256("${path.module}/llm-scripts/${file}")}"
    ]))
  }

  provisioner "local-exec" {
    command = "ansible-playbook -i ${path.module}/inventory.ini ${path.module}/llm.yml"
  }

  depends_on = [
    proxmox_virtual_environment_vm.llm_vm
  ]
}
