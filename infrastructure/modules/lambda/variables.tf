variable "function_name" {
  description = "Lambda name; limited to 54 characters to leave room for the IAM role suffix."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{1,54}$", var.function_name))
    error_message = "Use 1 to 54 letters, digits, underscores, or hyphens."
  }
}

variable "source_file" {
  description = "Path to handler.py. Defaults to the repository health handler; pass an absolute path when using Terragrunt source caching."
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days; indefinite retention is not allowed."
  type        = number
  default     = 14

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "Choose a supported, finite CloudWatch Logs retention period."
  }
}

variable "permissions_boundary_arn" {
  description = "Optional pre-provisioned IAM boundary limiting the execution role's maximum permissions."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to the Lambda, execution role, and log group."
  type        = map(string)
  default     = {}
}

variable "backend" {
  description = "Private ALB settings from ignored configuration; null explicitly disconnects the backend."
  type = object({
    url               = string
    subnet_ids        = list(string)
    security_group_id = string
  })
  default   = null
  sensitive = true
  validation {
    condition = var.backend == null ? true : (
      can(regex("^http://internal-clinical-trial-risk-dev-alb-[a-zA-Z0-9-]+\\.us-east-1\\.elb\\.amazonaws\\.com$", var.backend.url)) &&
      length(toset(var.backend.subnet_ids)) == 2 &&
      alltrue([for id in var.backend.subnet_ids : can(regex("^subnet-[0-9a-f]+$", id))]) &&
      can(regex("^sg-[0-9a-f]+$", var.backend.security_group_id))
    )
    error_message = "Use the project's internal ALB, two existing subnets, and its dedicated client security group."
  }
}
