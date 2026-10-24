# Copy to deployment.local.hcl and replace every example value before use.
# These identifiers are illustrative, not live deployment settings or credentials.
locals {
  aws_account_id       = "123456789012"
  state_bucket         = "clinical-trial-site-risk-monitor-tfstate-dev-123456789012"
  github_repository    = "example-owner/example-repository"
  github_owner_id      = "123456"
  github_repository_id = "789012"
}
