variable "cluster_name" { type = string }
variable "cluster_endpoint" {
  type      = string
  sensitive = true
}
variable "cluster_certificate" {
  type      = string
  sensitive = true
}
variable "image_uri" {
  description = "Previously published project ECR image pinned by digest, never a mutable tag."
  type        = string
  sensitive   = true
  validation {
    condition     = can(regex("^[0-9]{12}\\.dkr\\.ecr\\.us-east-1\\.amazonaws\\.com/clinical-trial-site-risk-monitor-dev-risk-service@sha256:[a-f0-9]{64}$", var.image_uri))
    error_message = "Use a digest-pinned image from the project's private ECR repository."
  }
}
variable "site_example_json" {
  description = "Synthetic example used by the in-cluster verification job."
  type        = string
}
variable "verification_run_id" {
  description = "Workflow run identifier forces a fresh verification job on every deployment."
  type        = string
}
