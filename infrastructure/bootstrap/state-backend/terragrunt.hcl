terraform_binary              = "terraform"
terraform_version_constraint  = ">= 1.10.0, < 2.0.0"
terragrunt_version_constraint = ">= 1.1.6, < 2.0.0"

# Keep bootstrap state separate from the bucket it manages and outside any cache.
generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    terraform {
      backend "local" {
        path = ${jsonencode("${replace(get_repo_root(), "\\", "/")}/infrastructure/state/bootstrap/terraform.tfstate")}
      }
    }
  EOF
}
