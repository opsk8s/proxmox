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
    data = templatefile("${path.module}/cloud-init.yaml", {
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
        address = "${var.lan_ip}/${split("/", var.lan_network)[1]}"
        gateway = var.lan_gateway
      }
    }

    dns {
      domain  = "lan"
      servers = [var.dns_ip, var.lan_gateway]
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

  lifecycle {
    action_trigger {
      events     = [after_create, after_update]
      actions    = [action.ansible_playbook_run.configure_jenkins]
      on_failure = halt
    }
  }
}

action "ansible_playbook_run" "configure_jenkins" {
  config {
    playbooks        = ["${path.module}/ansible.yml"]
    inventory_files  = ["${path.module}/inventory.ini"]
    private_key_file = var.ssh_private_key_file
    extra_vars = {
      jenkins_admin_password = var.jenkins_admin_password
      ansible_host           = var.lan_ip
      jenkins_http_host      = var.lan_ip
      jenkins_agent_host     = var.jenkins_agent_ip
    }
  }
}
