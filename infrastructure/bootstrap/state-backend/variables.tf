variable "aws_account_id" {
  description = "Expected AWS account from private deployment settings."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "Supply a 12-digit AWS account ID."
  }
}

variable "state_bucket" {
  description = "Project-specific state bucket name from private deployment settings."
  type        = string
}
