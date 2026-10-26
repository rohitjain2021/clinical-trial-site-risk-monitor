locals {
  notification = read_terragrunt_config("${get_terragrunt_dir()}/notifications.local.hcl").locals
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/infrastructure/modules/notifications"
}

inputs = {
  email = local.notification.email
}
