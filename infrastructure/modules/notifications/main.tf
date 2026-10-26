terraform {
  required_version = ">= 1.10.0, < 2.0.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

variable "email" {
  description = "Operator's demo notification email, supplied only through ignored local settings."
  type        = string
  sensitive   = true
  validation {
    condition     = can(regex("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", var.email))
    error_message = "Supply a valid notification email address in private local configuration."
  }
}

variable "tags" {
  description = "Project and environment ownership tags."
  type        = map(string)
  default     = {}
}

resource "aws_sns_topic" "assessments" {
  name         = "clinical-trial-site-risk-monitor-dev-assessments"
  fifo_topic   = false
  display_name = "Clinical Trial Site Risk Monitor"
  tags         = var.tags
}

# Same-account IAM grants the application access. Deny insecure transport for all publishers.
resource "aws_sns_topic_policy" "transport" {
  arn = aws_sns_topic.assessments.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "RequireHttpsPublishing"
      Effect    = "Deny"
      Principal = "*"
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.assessments.arn
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

# AWS sends a confirmation email; the recipient must click its link themselves.
resource "aws_sns_topic_subscription" "email" {
  topic_arn              = aws_sns_topic.assessments.arn
  protocol               = "email"
  endpoint               = var.email
  endpoint_auto_confirms = false
}

output "topic_arn" {
  description = "Private identifier for the project assessment-event topic."
  value       = aws_sns_topic.assessments.arn
  sensitive   = true
}
