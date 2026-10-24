variable "aws_account_id" {
  description = "Target AWS account ID supplied by private deployment configuration."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "Supply a 12-digit AWS account ID."
  }
}

variable "state_bucket" {
  description = "Existing remote state bucket name supplied outside the repository."
  type        = string
}

variable "github_repository" {
  description = "Exact GitHub owner/repository authorized for main-branch OIDC."
  type        = string
}

variable "github_owner_id" {
  description = "Immutable GitHub owner ID used in the OIDC subject."
  type        = string
}

variable "github_repository_id" {
  description = "Immutable GitHub repository ID used in the OIDC subject."
  type        = string
}
