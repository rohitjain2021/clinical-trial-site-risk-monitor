variable "repository_name" {
  description = "Private repository name identifying the project, environment, and service."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*([._/-][a-z0-9]+)*$", var.repository_name)) && length(var.repository_name) >= 2 && length(var.repository_name) <= 256
    error_message = "Use a lowercase ECR repository name of 2 to 256 characters."
  }
}

variable "tags" {
  description = "Project and environment tags supplied by Terragrunt."
  type        = map(string)
  default     = {}
}
