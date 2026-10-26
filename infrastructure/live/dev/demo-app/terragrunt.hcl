locals {
  demo = read_terragrunt_config("${get_terragrunt_dir()}/demo.local.hcl").locals
}

include "root" { path = find_in_parent_folders("root.hcl") }

terraform { source = "${get_repo_root()}/infrastructure/modules/demo-app" }

dependency "eks" { config_path = "../eks" }

inputs = {
  cluster_name          = dependency.eks.outputs.cluster_name
  risk_service_role_arn = dependency.eks.outputs.risk_service_role_arn
  cluster_endpoint      = dependency.eks.outputs.cluster_endpoint
  cluster_certificate   = dependency.eks.outputs.cluster_certificate
  image_uri             = local.demo.image_uri
  verification_run_id   = local.demo.verification_run_id
  site_example_json     = file("${get_repo_root()}/docs/examples/site-assessment.json")
}
