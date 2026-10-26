include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/infrastructure/modules/ecr"
}

inputs = {
  repository_name = "clinical-trial-site-risk-monitor-dev-risk-service"
}
