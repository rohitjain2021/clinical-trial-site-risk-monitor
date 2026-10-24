include "root" {
  path = find_in_parent_folders("root.hcl")
}

# An operator manages CI's own permissions; the CI deployment role cannot edit them.
terraform {
  source = "${get_repo_root()}/infrastructure/modules/github-actions"
}
