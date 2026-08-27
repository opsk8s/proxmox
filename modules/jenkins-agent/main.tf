# jenkins agent vm
resource "proxmox_virtual_environment_file" "jenkins_agent_config" {
  content_type = "snippets"
  datastore_id = var.backup_dir
  node_name    = var.main_node

  source_raw {
    data = templatefile("${path.module}/jenkins-agent-config.yaml", {
      jenkins_public_key = trimspace(var.ssh_public_key)
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
    file_id      = var.ubuntu_image_id
    interface    = "virtio0"
    size         = 50
    backup       = true
  }

  network_device {
    bridge = "vmbr0"
  }
  keyboard_layout = "de-ch"

  depends_on = [
    proxmox_virtual_environment_file.jenkins_agent_config
  ]
}

resource "null_resource" "configure_jenkins_agent" {
  triggers = {
    vm_id    = proxmox_virtual_environment_vm.jenkins_agent_vm.id
    playbook = filesha256("${path.module}/jenkins-agent.yml")
  }

  # debugging jenkins
  # sudo journalctl -u jenkins.service -n 150 --no-pager
  # sudo rm -fR /var/lib/jenkins/ && sudo apt remove jenkins
  # journalctl -u jenkins.service --since "now" -f
  # journalctl -u jenkins.service -n 150 -f
  provisioner "local-exec" {
    command = "ansible-playbook -i ${path.module}/inventory.ini ${path.module}/jenkins-agent.yml"
    environment = {
      JENKINS_ADMIN_PASSWORD = var.jenkins_admin_password
      JENKINS_ADMIN_EMAIL    = var.jenkins_admin_email
      JENKINS_AGENT_SSH_KEY  = var.ssh_private_key
    }
  }

  depends_on = [
    proxmox_virtual_environment_vm.jenkins_agent_vm
  ]
}
