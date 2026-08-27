# 2026-08-27: pve-*.tf refactored into per-node modules under modules/.
# moved blocks preserve the existing state addresses (no destroy/create).
moved {
  from = proxmox_virtual_environment_file.llm_config
  to   = module.llm.proxmox_virtual_environment_file.llm_config
}
moved {
  from = proxmox_virtual_environment_vm.llm_vm
  to   = module.llm.proxmox_virtual_environment_vm.llm_vm
}
moved {
  from = null_resource.configure_llm
  to   = module.llm.null_resource.configure_llm
}

moved {
  from = proxmox_virtual_environment_file.jenkins_config
  to   = module.jenkins.proxmox_virtual_environment_file.jenkins_config
}
moved {
  from = proxmox_virtual_environment_vm.jenkins_vm
  to   = module.jenkins.proxmox_virtual_environment_vm.jenkins_vm
}
moved {
  from = null_resource.configure_jenkins
  to   = module.jenkins.null_resource.configure_jenkins
}

moved {
  from = proxmox_virtual_environment_file.jenkins_agent_config
  to   = module.jenkins_agent.proxmox_virtual_environment_file.jenkins_agent_config
}
moved {
  from = proxmox_virtual_environment_vm.jenkins_agent_vm
  to   = module.jenkins_agent.proxmox_virtual_environment_vm.jenkins_agent_vm
}
moved {
  from = null_resource.configure_jenkins_agent
  to   = module.jenkins_agent.null_resource.configure_jenkins_agent
}

moved {
  from = proxmox_virtual_environment_file.openwebui_config
  to   = module.open_webui.proxmox_virtual_environment_file.openwebui_config
}
moved {
  from = proxmox_virtual_environment_vm.openwebui_vm
  to   = module.open_webui.proxmox_virtual_environment_vm.openwebui_vm
}
moved {
  from = null_resource.configure_openwebui
  to   = module.open_webui.null_resource.configure_openwebui
}

moved {
  from = proxmox_virtual_environment_file.postgres_config
  to   = module.postgres.proxmox_virtual_environment_file.postgres_config
}
moved {
  from = proxmox_virtual_environment_vm.postgres_vm
  to   = module.postgres.proxmox_virtual_environment_vm.postgres_vm
}
moved {
  from = null_resource.configure_postgres
  to   = module.postgres.null_resource.configure_postgres
}
