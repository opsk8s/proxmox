# used physical cores 8 + 1 + 2 + 1 = 13
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
    datastore_id = var.os_ssd_fast # or use a different datastore
    interface    = "virtio1"
    size         = 200 # size in GB
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
    proxmox_virtual_environment_file.llm_config,
    proxmox_download_file.ubuntu_cloud_image,
    proxmox_download_file.fedora_cloud_image
  ]
}


# AMD
# sudo amd-smi set -g 0 1 2 3 -P COMPUTE
# sudo amd-smi set -o 300 -l HIGH
resource "null_resource" "configure_llm" {
  triggers = {
    vm_id    = proxmox_virtual_environment_vm.llm_vm.id
    playbook = filesha256("${path.module}/vms/pve/llm.yml")
    files = sha256(join("", [
      for file in fileset("${path.module}/vms/pve/llm-scripts", "*") :
      "${file}:${filesha256("${path.module}/vms/pve/llm-scripts/${file}")}"
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

  agent {
    enabled = true
  }

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
  // 1 physical
  cpu {
    sockets = 1
    cores   = 2
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
      jenkins_public_key = trimspace(data.local_file.jenkins_public_key.content)
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

  agent {
    enabled = true
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.51.203/24"
        gateway = "192.168.51.1"
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.jenkins_agent_config.id
  }
  // 2 physical
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

  # debugging jenkins
  # sudo journalctl -u jenkins.service -n 150 --no-pager
  # sudo rm -fR /var/lib/jenkins/ && sudo apt remove jenkins
  # journalctl -u jenkins.service --since "now" -f
  # journalctl -u jenkins.service -n 150 -f
  provisioner "local-exec" {
    command = "ansible-playbook -i vms/pve/inventory.ini vms/pve/jenkins-agent.yml"
    environment = {
      JENKINS_ADMIN_PASSWORD = var.jenkins_admin_password
      JENKINS_ADMIN_EMAIL    = var.jenkins_admin_email
      JENKINS_AGENT_SSH_KEY  = data.local_file.jenkins_private_key.content
    }
  }

  depends_on = [
    proxmox_virtual_environment_vm.jenkins_agent_vm
  ]
}

# open-webui vm
# WARNING: same cloud-init seed caveat as the jenkins VM above —
# changing the snippet after creation forces a FULL VM recreation.
resource "proxmox_virtual_environment_file" "openwebui_config" {
  content_type = "snippets"
  datastore_id = var.backup_dir
  node_name    = var.main_node

  source_raw {
    data = templatefile("${path.module}/vms/cloud-init/openwebui-config.yaml", {
      openwebui_public_key = trimspace(data.local_file.public_key.content)
    })
    file_name = "openwebui-config.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "openwebui_vm" {
  name            = "open-webui"
  node_name       = var.main_node
  vm_id           = 103
  tags            = ["ubuntu", "webui", "llm"]
  stop_on_destroy = true

  agent {
    enabled = true
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.51.204/24"
        gateway = "192.168.51.1"
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.openwebui_config.id
  }
  // one physical
  cpu {
    sockets = 1
    cores   = 2
    # the default qemu64 CPU exposes a baseline-only feature set (no SSE4.2/POPCNT)
    # and numpy 2.x wheels refuse to load on it; pass the host's features through
    type    = "host"
  }

  memory {
    dedicated = 4096
  }

  disk {
    datastore_id = var.vm_dir
    file_id      = proxmox_download_file.ubuntu_cloud_image.id
    interface    = "virtio0"
    size         = 32
    backup       = true
  }

  network_device {
    bridge = "vmbr0"
  }
  keyboard_layout = "de-ch"

  depends_on = [
    proxmox_virtual_environment_file.openwebui_config,
    proxmox_download_file.ubuntu_cloud_image,
    proxmox_download_file.fedora_cloud_image
  ]
}

resource "null_resource" "configure_openwebui" {
  triggers = {
    vm_id    = proxmox_virtual_environment_vm.openwebui_vm.id
    playbook = filesha256("${path.module}/vms/pve/open-webui.yml")
  }

  provisioner "local-exec" {
    command = "ansible-playbook -i vms/pve/inventory.ini vms/pve/open-webui.yml"
  }

  depends_on = [
    proxmox_virtual_environment_vm.openwebui_vm
  ]
}
