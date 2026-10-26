locals {
  environment = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  backend     = read_terragrunt_config("${get_terragrunt_dir()}/backend.local.hcl", { locals = { backend = null } }).locals.backend
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Terragrunt copies the module into its cache before running Terraform.
terraform {
  source = "${get_repo_root()}/infrastructure/modules/lambda"
}

inputs = {
  function_name            = "clinical-trial-site-risk-monitor-dev"
  log_retention_days       = 14
  permissions_boundary_arn = "arn:aws:iam::${local.environment.aws_account_id}:policy/clinical-trial-site-risk-monitor-dev-lambda-boundary"
  # An absolute path lets the cached module package the original handler reliably.
  source_file = "${get_repo_root()}/services/lambda/handler.py"
  backend     = local.backend
}
