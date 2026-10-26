terraform {
  required_version = ">= 1.10.0, < 2.0.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

variable "api_execution_arn" {
  description = "Existing project HTTP API execution ARN, supplied by the Lambda unit."
  type        = string
  sensitive   = true
  validation {
    condition     = can(regex("^arn:aws:execute-api:us-east-1:[0-9]{12}:[a-z0-9]+$", var.api_execution_arn))
    error_message = "Supply the existing us-east-1 API execution ARN without a route wildcard."
  }
}

variable "tags" {
  description = "Project and environment ownership tags."
  type        = map(string)
  default     = {}
}

locals {
  name = "clinical-trial-site-risk-monitor-dev-streamlit"
  invoke_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "execute-api:Invoke"
      Resource = "${var.api_execution_arn}/dev/POST/site-assessments"
    }]
  })
}

# Community Cloud has no AWS instance role. Give its server a dedicated API-only
# identity; the boundary also prevents later attached policies broadening access.
resource "aws_iam_policy" "boundary" {
  name   = "${local.name}-boundary"
  policy = local.invoke_policy
  tags   = var.tags
}

resource "aws_iam_user" "ui" {
  name                 = local.name
  permissions_boundary = aws_iam_policy.boundary.arn
  force_destroy        = false
  tags                 = var.tags
}

resource "aws_iam_user_policy" "invoke" {
  name   = "invoke-site-assessment-only"
  user   = aws_iam_user.ui.name
  policy = local.invoke_policy
}

# The secret is sensitive but remains in encrypted Terraform state. Never print
# this output in CI; export it only into ignored local Streamlit configuration.
resource "aws_iam_access_key" "ui" {
  user = aws_iam_user.ui.name
  lifecycle { create_before_destroy = true }
}

output "app_secrets" {
  description = "Private Community Cloud settings; export to an ignored file, never logs."
  sensitive   = true
  value = {
    risk_api = { base_url = "https://${split(":", var.api_execution_arn)[5]}.execute-api.us-east-1.amazonaws.com/dev" }
    aws      = { access_key_id = aws_iam_access_key.ui.id, secret_access_key = aws_iam_access_key.ui.secret }
  }
}
