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