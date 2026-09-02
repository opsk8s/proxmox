# jenkins agent vm
resource "proxmox_virtual_environment_file" "jenkins_agent_config" {
  content_type = "snippets"
  datastore_id = var.backup_dir
  node_name    = var.main_node

  source_raw {
    data = templatefile("${path.module}/cloud-init.yaml", {
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
        address = "${var.lan_ip}/${split("/", var.lan_network)[1]}"
        gateway = var.lan_gateway
      }
    }

    dns {
      domain  = "lan"
      servers = [var.dns_ip, var.lan_gateway]
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

  lifecycle {
    action_trigger {
      events     = [after_create, after_update]
      actions    = [action.ansible_playbook_run.configure_jenkins_agent]
      on_failure = halt
    }
  }
}

# debugging jenkins
# sudo journalctl -u jenkins.service -n 150 --no-pager
# sudo rm -fR /var/lib/jenkins/ && sudo apt remove jenkins
# journalctl -u jenkins.service --since "now" -f
# journalctl -u jenkins.service -n 150 -f
# NOTE: uses the jenkins-agent key, not the shared proxmox-ubuntu key
action "ansible_playbook_run" "configure_jenkins_agent" {
  config {
    playbooks        = ["${path.module}/ansible.yml"]
    inventory_files  = ["${path.module}/inventory.ini"]
    private_key_file = var.ssh_private_key_file
    extra_vars = {
      ansible_host = var.lan_ip
    }
  }
}
