
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
        groups:
          - sudo
          - render
          - video
        shell: /bin/bash
        ssh_authorized_keys:
          - ${trimspace(data.local_file.llm_public_key.content)}
        sudo: ALL=(ALL) NOPASSWD:ALL
    package_update: true
    package_upgrade: true
    packages:
      - qemu-guest-agent
      - net-tools
      - curl
      - openssh-server
      - nvtop
      - btop
      - libatomic1
      - libquadmath0
      - amdgpu-dkms
      - amdrocm7.14-gfx1201
    bootcmd:
      - mkdir -p -m 0755 /etc/apt/keyrings
      - mkdir -p -m 0755 /mnt/models
      - wget -qO- https://repo.radeon.com/rocm/rocm.gpg.key | gpg --dearmor -o /etc/apt/keyrings/rocm.gpg
      - echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/amdgpu/31.40.1/ubuntu resolute main" > /etc/apt/sources.list.d/amdgpu.list
      - wget https://repo.amd.com/rocm/packages-multi-arch/gpg/rocm.gpg -O - | gpg --dearmor | sudo tee /etc/apt/keyrings/amdrocm.gpg > /dev/null
      - echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/amdrocm.gpg] https://repo.amd.com/rocm/packages-multi-arch/ubuntu2604 stable main" > /etc/apt/sources.list.d/rocm.list
    write_files:
      - path: /etc/udev/rules.d/70-amdgpu.rules
        owner: root:root
        permissions: '0644'
        content: |
          KERNEL=="kfd", GROUP="render", MODE="0666"
          SUBSYSTEM=="drm", KERNEL=="renderD*", GROUP="render", MODE="0666"
    runcmd:
      - mount -t virtiofs llm-models /mnt/models
      - chown -R llm:llm /mnt/models
      - systemctl enable qemu-guest-agent
      - systemctl start qemu-guest-agent
      - systemctl enable --now ssh
      - udevadm control --reload-rules
      - udevadm trigger
      - echo "done" > /tmp/cloud-config.done
      - reboot
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

  hostpci {
    device = "hostpci0"
    id     = "0000:03:00"
  }

  hostpci {
    device = "hostpci1"
    id     = "0000:2d:00"
  }

  hostpci {
    device = "hostpci2"
    id     = "0000:43:00"
  }

  hostpci {
    device = "hostpci3"
    id     = "0000:63:00"
  }

  keyboard_layout = "de-ch"

  depends_on = [
    proxmox_virtual_environment_file.llm_config,
    proxmox_download_file.ubuntu_cloud_image,
    proxmox_download_file.fedora_cloud_image
  ]
}
