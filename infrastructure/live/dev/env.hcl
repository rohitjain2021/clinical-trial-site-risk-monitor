# Deployment identifiers come from an ignored file, created locally or by CI.
locals {
  deployment       = read_terragrunt_config("${get_terragrunt_dir()}/deployment.local.hcl").locals
  environment_name = "dev"
  aws_region       = "us-east-1"
  aws_account_id   = local.deployment.aws_account_id
  state_bucket     = local.deployment.state_bucket
}
