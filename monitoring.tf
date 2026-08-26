# ---------------------------------------------------------------------------
# Monitoring stack (Prometheus + Grafana + blackbox_exporter)
#
# Runs in a lightweight LXC (2 cores / 2GB / 10GB) so it does not steal
# physical cores from the LLM workload (the host is fully allocated).
#
# The OS template must ALREADY exist in a datastore: Proxmox's template
# mirror is subscription-gated, so it cannot be downloaded unconditionally.
# Find a template with `pveam list` on the PVE host (or GUI: Datacenter ->
# Storage -> <store> -> Content -> "Template OS") and set ct_template_file_id
# in proxmox.tfvars, e.g.:
#   ct_template_file_id = "backup-slow-dir:vztmpl/ubuntu-26.04-....vztmpl"
#
# Endpoints once running (Grafana :3000, Prometheus :9090 on 192.168.51.206).
# ---------------------------------------------------------------------------
# PVE runs this script as root inside the CT on every start. It guarantees
# the static IP, DNS, openssh-server and the management key — idempotent,
# and self-healing if the template's cloud-init did not apply them (this
# provider version cannot pass a #cloud-config user-data file to CTs).
resource "proxmox_virtual_environment_file" "monitoring_bootstrap_hook" {
  content_type = "snippets"
  # The provider uploads snippets over SSH (not via the PVE API) and leaves
  # default 0644 perms unless file_mode is set. PVE refuses to create a CT
  # whose hookscript is not executable, so the script must land with +x.
  file_mode    = "0755"
  datastore_id = var.backup_dir
  node_name    = var.main_node

  source_raw {
    data = templatefile("${path.module}/vms/pve/dashboards/monitoring-bootstrap.sh", {
      monitoring_public_key = trimspace(data.local_file.public_key.content)
    })
    file_name = "monitoring-bootstrap.sh"
  }
}

resource "proxmox_virtual_environment_container" "monitoring" {
  node_name     = var.main_node
  vm_id         = 200
  tags          = ["monitoring", "prometheus", "grafana"]
  unprivileged  = true
  start_on_boot = true

  operating_system {
    template_file_id = var.ct_template_file_id
  }

  hook_script_file_id = proxmox_virtual_environment_file.monitoring_bootstrap_hook.id

  initialization {
    hostname = "monitoring"

    # PVE OS templates inject the SSH key for the default user (root),
    # so ansible connects as root.
    user_account {
      keys = [trimspace(data.local_file.public_key.content)]
    }

    ip_config {
      ipv4 {
        address = "192.168.51.206/24"
        gateway = "192.168.51.1"
      }
    }
  }

  wait_for_ip {
    ipv4 = true
  }

  startup {
    order = 5
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = var.vm_dir
    size         = 10
  }

  network_interface {
    name   = "net0"
    bridge = "vmbr0"
  }
}

resource "null_resource" "configure_monitoring" {
  triggers = {
    ct_id    = proxmox_virtual_environment_container.monitoring.id
    playbook = filesha256("${path.module}/vms/pve/monitoring.yml")
    dashboards = sha256(join("", [
      for file in fileset("${path.module}/vms/pve/dashboards", "*.json") :
      "${file}:${filesha256("${path.module}/vms/pve/dashboards/${file}")}"
    ]))
  }

  provisioner "local-exec" {
    command = "ansible-playbook -i vms/pve/inventory.ini vms/pve/monitoring.yml"
    environment = {
      GRAFANA_ADMIN_PASSWORD = var.grafana_admin_password
    }
  }

  depends_on = [
    proxmox_virtual_environment_container.monitoring
  ]
}

# Runs node_exporter on every VM plus the service-specific exporters
# (GPU collector on llm, postgres_exporter on postgres, Jenkins
# prometheus plugin on the controller). Must run AFTER the service
# playbooks so the scraped services exist.
resource "null_resource" "configure_exporters" {
  triggers = {
    playbook      = filesha256("${path.module}/vms/pve/exporters.yml")
    gpu_collector = filesha256("${path.module}/vms/pve/dashboards/gpu-metrics.py")
  }

  provisioner "local-exec" {
    command = "ansible-playbook -i vms/pve/inventory.ini vms/pve/exporters.yml"
    environment = {
      JENKINS_ADMIN_PASSWORD = var.jenkins_admin_password
      POSTGRES_PASSWORD      = var.postgres_password
    }
  }

  depends_on = [
    null_resource.configure_llm,
    null_resource.configure_jenkins,
    null_resource.configure_jenkins_agent,
    null_resource.configure_openwebui,
    null_resource.configure_postgres,
  ]
}

output "grafana_url" {
  value     = "http://192.168.51.206:3000"
  sensitive = false
}
