# VM - llm
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
        address = "192.168.51.201/24"
        gateway = "192.168.51.1"
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.llm_config.id
  }

  cpu {
    sockets = 1
    cores   = 16
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
    id = "0000:03:00"
  }
  # GPU 2
  hostpci {
    device = "hostpci1"
    id = "0000:2d:00"
  }
  # GPU 3
  hostpci {
    device = "hostpci2"
    id = "0000:43:00"
  }
  # GPU 4
  hostpci {
    device = "hostpci3"
    id = "0000:63:00"
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

# vm jenkins
resource "proxmox_virtual_environment_file" "jenkins_config" {
  content_type = "snippets"
  datastore_id = var.backup_dir
  node_name    = var.main_node

  source_raw {
    data = <<-EOF
    #cloud-config
    hostname: jenkins-ubuntu
    timezone: Europe/Zurich
    users:
      - name: jenkins
        groups: [sudo]
        shell: /bin/bash
        ssh_authorized_keys:
          - ${trimspace(data.local_file.llm_public_key.content)}
        sudo: ALL=(ALL) NOPASSWD:ALL
    packages:
      - qemu-guest-agent
      - openssh-server
    EOF

    file_name = "jenkins-config.yaml"
  }
}


resource "proxmox_virtual_environment_vm" "jenkins_vm" {
  name            = "jenkins-ubuntu"
  node_name       = var.main_node
  vm_id           = 101
  tags            = ["ubuntu", "jenkins"]
  stop_on_destroy = true

  initialization {
    # uncomment and specify the datastore for cloud-init disk if default `local-lvm` is not available
    # datastore_id = "local-lvm"

    ip_config {
      ipv4 {
        address = "192.168.51.202/24"
        gateway = "192.168.51.1"
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.jenkins_config.id
  }

  cpu {
    sockets = 1
    cores   = 4
  }

  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = var.vm_dir
    file_id      = proxmox_download_file.ubuntu_cloud_image.id
    interface    = "virtio0"
    size         = 40
    backup       = true
  }

  virtiofs {
    mapping   = proxmox_hardware_mapping_dir.git_storage_mapping.id
    cache     = "always"
    direct_io = true
  }

  network_device {
    bridge = "vmbr0"
  }
  keyboard_layout = "de-ch"

  depends_on = [
    proxmox_virtual_environment_file.jenkins_config,
    proxmox_download_file.ubuntu_cloud_image,
    proxmox_download_file.fedora_cloud_image
  ]
}