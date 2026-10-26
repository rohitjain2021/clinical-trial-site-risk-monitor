variable "cluster_name" {
  description = "Project and environment name used for the cluster and supporting resources."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,41}$", var.cluster_name))
    error_message = "Use 2 to 42 lowercase letters, digits, or hyphens so supporting IAM role names stay within limits."
  }
}

variable "kubernetes_version" {
  description = "Explicit Kubernetes minor version; confirm standard support before applying."
  type        = string
  default     = "1.36"
}

variable "availability_zones" {
  description = "Two existing default subnet zones in us-east-1; no network resources are adopted."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
  validation {
    condition     = length(var.availability_zones) == 2 && length(toset(var.availability_zones)) == 2
    error_message = "Supply two distinct Availability Zones."
  }
}

variable "admin_principal_arn" {
  description = "Existing operator IAM user or role, supplied through ignored local configuration."
  type        = string
  sensitive   = true
  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:(user|role)/.+$", var.admin_principal_arn))
    error_message = "Use an IAM user or role ARN, not root or an assumed-role session ARN."
  }
}

variable "admin_cidrs" {
  description = "Explicit trusted public IPv4 /32 addresses allowed to reach the cluster API."
  type        = list(string)
  sensitive   = true
  validation {
    condition     = length(var.admin_cidrs) > 0 && alltrue([for cidr in var.admin_cidrs : can(cidrnetmask(cidr)) && endswith(cidr, "/32")])
    error_message = "Supply at least one valid IPv4 /32; do not expose the API to the whole internet."
  }
}

variable "image_repository_name" {
  description = "Existing private ECR repository from which risk-service images can be pulled."
  type        = string
}

variable "tags" {
  description = "Project, environment, and infrastructure management tags supplied by Terragrunt."
  type        = map(string)
  default     = {}
}

variable "role_boundaries" {
  description = "Operator-managed boundaries for cluster, node, CNI, and risk-service roles."
  type        = map(string)
  validation {
    condition     = alltrue([for key in ["cluster", "nodes", "cni", "risk"] : can(regex("^arn:aws:iam::(aws|[0-9]{12}):policy/.+$", var.role_boundaries[key]))])
    error_message = "Supply all four operator-managed role boundary ARNs."
  }
}

variable "demo_principal_arn" {
  description = "Main-only demo workflow role, with access tracked separately from the operator."
  type        = string
  sensitive   = true
}
