resource "proxmox_storage_directory" "llm_models" {
  id    = "llm-models"
  path  = "/os-ssd-fast/models"
  nodes = [var.main_node]

  content = ["images"]
  shared  = true
  disable = false

  backups {
    max_protected_backups = 3
    keep_daily            = 7
  }
}

resource "proxmox_storage_directory" "git_storage" {
  id    = "git-server"
  path  = "/os-ssd-fast/git"
  nodes = [var.main_node]

  content = ["images"]
  shared  = true
  disable = false

  backups {
    max_protected_backups = 3
    keep_daily            = 7
  }
}

# Map the models directory
resource "proxmox_hardware_mapping_dir" "llm_models_mapping" {
  name = "llm-models" # This is the "tag" we will mount inside the VM

  map = [
    {
      node = var.main_node
      path = proxmox_storage_directory.llm_models.path # Uses "/os-ssd-fast/models"
    }
  ]
}

# Map the git directory
resource "proxmox_hardware_mapping_dir" "git_storage_mapping" {
  name = "git-server" # This is the "tag" we will mount inside the VM

  map = [
    {
      node = var.main_node
      path = proxmox_storage_directory.git_storage.path # Uses "/os-ssd-fast/git"
    }
  ]
}
