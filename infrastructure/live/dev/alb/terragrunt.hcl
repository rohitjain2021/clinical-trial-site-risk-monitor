include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/infrastructure/modules/alb"
}

dependency "eks" { config_path = "../eks" }
dependency "app" { config_path = "../demo-app" }

locals {
  application = read_terragrunt_config("../demo-app/demo.local.hcl").locals
}

inputs = {
  vpc_id                        = dependency.eks.outputs.vpc_id
  subnet_ids                    = dependency.eks.outputs.subnet_ids
  worker_security_group_id      = dependency.eks.outputs.cluster_security_group_id
  worker_autoscaling_group_name = dependency.eks.outputs.worker_autoscaling_group_name
  cluster_name                  = dependency.eks.outputs.cluster_name
  cluster_endpoint              = dependency.eks.outputs.cluster_endpoint
  cluster_certificate           = dependency.eks.outputs.cluster_certificate
  node_port                     = dependency.app.outputs.node_port
  namespace                     = dependency.app.outputs.namespace
  image_uri                     = dependency.app.outputs.image_uri
  site_example_json             = file("${get_repo_root()}/docs/examples/site-assessment.json")
  verification_script           = file("${get_repo_root()}/infrastructure/modules/demo-app/verify.py")
  verification_run_id           = local.application.verification_run_id
}
