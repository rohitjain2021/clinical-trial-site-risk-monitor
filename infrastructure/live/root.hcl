# Shared configuration keeps provider settings and state paths consistent across units.
locals {
  environment = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
}

terraform_binary              = "terraform"
terraform_version_constraint  = ">= 1.10.0, < 2.0.0"
terragrunt_version_constraint = ">= 1.1.6, < 2.0.0"

# Pin the account as well as the region; credentials remain outside this repository.
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      region              = ${jsonencode(local.environment.aws_region)}
      allowed_account_ids = [${jsonencode(local.environment.aws_account_id)}]
    }
  EOF
}

# The bootstrap Terraform stack owns this bucket; Terragrunt only configures its use.
# Native S3 lock files serialize state changes without a DynamoDB table.
generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    terraform {
      backend "s3" {
        bucket              = ${jsonencode(local.environment.state_bucket)}
        key                 = ${jsonencode("${replace(path_relative_to_include(), "\\", "/")}/terraform.tfstate")}
        region              = ${jsonencode(local.environment.aws_region)}
        allowed_account_ids = [${jsonencode(local.environment.aws_account_id)}]
        encrypt             = true
        use_lockfile        = true
      }
    }
  EOF
}

inputs = {
  tags = {
    Project     = "clinical-trial-site-risk-monitor"
    Environment = local.environment.environment_name
    ManagedBy   = "Terraform-Terragrunt"
  }
}
