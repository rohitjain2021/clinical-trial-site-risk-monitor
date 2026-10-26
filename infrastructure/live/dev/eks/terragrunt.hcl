locals {
  operator    = read_terragrunt_config("${get_terragrunt_dir()}/eks.local.hcl").locals
  environment = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/infrastructure/modules/eks"
}

dependency "ecr" {
  config_path = "../ecr"
}

inputs = {
  role_boundaries = {
    cluster = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
    nodes   = "arn:aws:iam::${local.environment.aws_account_id}:policy/clinical-trial-site-risk-monitor-dev-eks-nodes-boundary"
    cni     = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
    risk    = "arn:aws:iam::${local.environment.aws_account_id}:policy/clinical-trial-site-risk-monitor-dev-eks-risk-service-boundary"
  }
  demo_principal_arn    = "arn:aws:iam::${local.environment.aws_account_id}:role/clinical-trial-site-risk-monitor-dev-github-demo"
  cluster_name          = "clinical-trial-site-risk-monitor-dev-eks"
  kubernetes_version    = "1.36"
  availability_zones    = ["us-east-1a", "us-east-1b"]
  admin_principal_arn   = local.operator.admin_principal_arn
  admin_cidrs           = local.operator.admin_cidrs
  image_repository_name = dependency.ecr.outputs.repository_name
}
