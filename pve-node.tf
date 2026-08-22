# VM - llm
resource "proxmox_virtual_environment_file" "llm_config" {
  content_type = "snippets"
  datastore_id = var.backup_dir
  node_name    = var.main_node

  source_raw {
    data = templatefile("${path.module}/vms/cloud-init/llm-config.yaml", {
      llm_public_key = trimspace(data.local_file.public_key.content)
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
    dedicated = 65536
  }

  disk {
    datastore_id = var.vm_dir
    file_id      = proxmox_download_file.ubuntu_cloud_image.id
    interface    = "virtio0"
    size         = 100
    backup       = true
  }

  # Second disk (additional storage)
  disk {
    datastore_id = var.os_ssd_fast  # or use a different datastore
    interface    = "virtio1"
    size         = 200          # size in GB
    backup       = true
    # file_format = "raw"      # optional: specify format (raw, qcow2)
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
    playbook = filesha256("${path.module}/vms/pve/llm.yml")
    files = sha256(join("", [
      for file in fileset("${path.module}/vms/pve/scripts", "*") :
      "${file}:${filesha256("${path.module}/vms/pve/scripts/${file}")}"
    ]))
  }

  provisioner "local-exec" {
    command = "ansible-playbook -i vms/pve/inventory.ini vms/pve/llm.yml"
  }

  depends_on = [
    proxmox_virtual_environment_vm.llm_vm
  ]
}

# jenkins vm
# WARNING: the PVE provider cannot update a cloud-init seed on an existing VM.
# Changing the content of this snippet (e.g. the hostname) forces a FULL VM
# recreation and wipes the disk. Set the hostname in the playbook (hostnamectl)
# instead of here, and never edit this file after the VM is created.
resource "proxmox_virtual_environment_file" "jenkins_config" {
  content_type = "snippets"
  datastore_id = var.backup_dir
  node_name    = var.main_node

  source_raw {
    data = templatefile("${path.module}/vms/cloud-init/jenkins-config.yaml", {
      jenkins_public_key = trimspace(data.local_file.public_key.content)
    })
    file_name = "jenkins-config.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "jenkins_vm" {
  name            = "jenkins-server"
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

resource "null_resource" "configure_jenkins" {
  triggers = {
    vm_id    = proxmox_virtual_environment_vm.jenkins_vm.id
    playbook = filesha256("${path.module}/vms/pve/jenkins.yml")
  }

  provisioner "local-exec" {
    command = "ansible-playbook -i vms/pve/inventory.ini vms/pve/jenkins.yml"
    environment = {
      # read by the playbook via lookup('env', 'JENKINS_ADMIN_PASSWORD')
      JENKINS_ADMIN_PASSWORD = var.jenkins_admin_password
    }
  }

  depends_on = [
    proxmox_virtual_environment_vm.jenkins_vm
  ]
}

# jenkins agent vm
resource "proxmox_virtual_environment_file" "jenkins_agent_config" {
  content_type = "snippets"
  datastore_id = var.backup_dir
  node_name    = var.main_node

  source_raw {
    data = templatefile("${path.module}/vms/cloud-init/jenkins-agent-config.yaml", {
      jenkins_public_key = trimspace(data.local_file.jenkins_agent_key.content)
    })
    file_name = "jenkins-agent-config.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "jenkins_agent_vm" {
  name            = "jenkins-agent"
  node_name       = var.main_node
  vm_id           = 102
  tags            = ["ubuntu", "jenkins", "agents"]
  stop_on_destroy = true

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.51.203/24"
        gateway = "192.168.51.1"
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.jenkins_agent_config.id
  }

  cpu {
    sockets = 1
    cores   = 8
  }

  memory {
    dedicated = 8192
  }

  disk {
    datastore_id = var.vm_dir
    file_id      = proxmox_download_file.ubuntu_cloud_image.id
    interface    = "virtio0"
    size         = 50
    backup       = true
  }

  network_device {
    bridge = "vmbr0"
  }
  keyboard_layout = "de-ch"

  depends_on = [
    proxmox_virtual_environment_file.jenkins_agent_config,
    proxmox_download_file.ubuntu_cloud_image,
    proxmox_download_file.fedora_cloud_image
  ]
}

resource "null_resource" "configure_jenkins_agent" {
  triggers = {
    vm_id    = proxmox_virtual_environment_vm.jenkins_agent_vm.id
    playbook = filesha256("${path.module}/vms/pve/jenkins-agent.yml")
  }

  provisioner "local-exec" {
    command = "ansible-playbook -i vms/pve/inventory.ini vms/pve/jenkins-agent.yml"
  }

  depends_on = [
    proxmox_virtual_environment_vm.jenkins_agent_vm
  ]
}