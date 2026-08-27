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
    data = templatefile("${path.module}/jenkins-config.yaml", {
      jenkins_public_key = trimspace(var.ssh_public_key)
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
    file_id      = var.ubuntu_image_id
    interface    = "virtio0"
    size         = 40
    backup       = true
  }

  network_device {
    bridge = "vmbr0"
  }
  keyboard_layout = "de-ch"

  depends_on = [
    proxmox_virtual_environment_file.jenkins_config
  ]
}

resource "null_resource" "configure_jenkins" {
  triggers = {
    vm_id    = proxmox_virtual_environment_vm.jenkins_vm.id
    playbook = filesha256("${path.module}/jenkins.yml")
  }

  provisioner "local-exec" {
    command = "ansible-playbook -i ${path.module}/inventory.ini ${path.module}/jenkins.yml"
    environment = {
      # read by the playbook via lookup('env', 'JENKINS_ADMIN_PASSWORD')
      JENKINS_ADMIN_PASSWORD = var.jenkins_admin_password
    }
  }

  depends_on = [
    proxmox_virtual_environment_vm.jenkins_vm
  ]
}
