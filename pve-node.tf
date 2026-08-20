
resource "proxmox_virtual_environment_file" "llm_config" {
  content_type = "snippets"
  datastore_id = var.backup_dir
  node_name    = var.main_node

  source_raw {
    data = <<-EOF
    #cloud-config
    hostname: llm-ubuntu
    timezone: Europe/Zurich
    users:
      - name: llm
        groups: [sudo]
        shell: /bin/bash
        ssh_authorized_keys:
          - ${trimspace(data.local_file.llm_public_key.content)}
        sudo: ALL=(ALL) NOPASSWD:ALL
    packages:
      - qemu-guest-agent
      - openssh-server
    EOF

    file_name = "llm-config.yaml"
  }
}


resource "proxmox_virtual_environment_vm" "llm_vm" {
  name            = "llm-ubuntu"
  node_name       = var.main_node
  vm_id           = 100
  tags            = ["ubuntu", "llm", "rocm", "amd"]
  stop_on_destroy = true

  initialization {
    # uncomment and specify the datastore for cloud-init disk if default `local-lvm` is not available
    # datastore_id = "local-lvm"

    ip_config {
      ipv4 {
        address = "192.168.51.142/24"
        gateway = "192.168.51.1"
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.llm_config.id
  }

  cpu {
    sockets = 1
    cores   = 8
  }

  memory {
    dedicated = 16384
  }

  disk {
    datastore_id = var.vm_dir
    file_id      = proxmox_download_file.ubuntu_cloud_image.id
    interface    = "virtio0"
    size         = 20
    backup       = true
  }

  virtiofs {
    mapping   = proxmox_hardware_mapping_dir.llm_models_mapping.name
    cache     = "always"
    direct_io = true
  }

  network_device {
    bridge = "vmbr0"
  }

  # GPU 1
  hostpci {
    device = "hostpci0"
    id = "0000:03:00.0"
  }
  hostpci {
    device = "hostpci1"
    id = "0000:03:00.1"
  }
  # GPU 2
  hostpci {
    device = "hostpci2"
    id = "0000:2d:00.0"
  }
  hostpci {
    device = "hostpci3"
    id = "0000:2d:00.1"
  }
  # GPU 3
  hostpci {
    device = "hostpci4"
    id = "0000:43:00.0"
  }
  hostpci {
    device = "hostpci5"
    id = "0000:43:00.1"
  }
  # GPU 4
  hostpci {
    device = "hostpci6"
    id = "0000:63:00.0"
  }
  hostpci {
    device = "hostpci7"
    id = "0000:63:00.1"
  }

  keyboard_layout = "de-ch"

  depends_on = [
    proxmox_virtual_environment_file.llm_config,
    proxmox_download_file.ubuntu_cloud_image,
    proxmox_download_file.fedora_cloud_image
  ]
}


resource "null_resource" "configure_llm" {
  triggers = {
    vm_id = proxmox_virtual_environment_vm.llm_vm.id
  }

  provisioner "local-exec" {
    command = "ansible-playbook -i vms/pve/inventory.ini vms/pve/llm.yml"
  }
}
