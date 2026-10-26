variable "vpc_id" {
  description = "Existing EKS VPC; this module must not create a network."
  type        = string
  sensitive   = true
}
variable "subnet_ids" {
  description = "Two existing EKS subnets in distinct Availability Zones."
  type        = list(string)
  sensitive   = true
  validation {
    condition     = length(var.subnet_ids) == 2 && length(toset(var.subnet_ids)) == 2
    error_message = "Use the two existing EKS subnets."
  }
}
variable "worker_security_group_id" {
  description = "EKS-owned worker security group; only a scoped ingress rule is added."
  type        = string
  sensitive   = true
}
variable "worker_autoscaling_group_name" {
  description = "EKS-managed risk-service worker group from the EKS unit output."
  type        = string
  sensitive   = true
  validation {
    condition     = startswith(var.worker_autoscaling_group_name, "eks-clinical-trial-site-risk-monitor-dev-eks-risk-nodes-")
    error_message = "Attach only the project's existing EKS risk-service worker group."
  }
}
variable "node_port" {
  description = "Fixed risk-service NodePort exported by the application unit."
  type        = number
  validation {
    condition     = var.node_port == 30800
    error_message = "Forward only to the project's risk-service port 30800."
  }
}
variable "cluster_name" { type = string }
variable "cluster_endpoint" {
  type      = string
  sensitive = true
}
variable "cluster_certificate" {
  type      = string
  sensitive = true
}
variable "namespace" { type = string }
variable "image_uri" {
  description = "Existing digest-pinned application image for the private HTTP test."
  type        = string
  sensitive   = true
  validation {
    condition     = can(regex("^[0-9]{12}\\.dkr\\.ecr\\.us-east-1\\.amazonaws\\.com/clinical-trial-site-risk-monitor-dev-risk-service@sha256:[a-f0-9]{64}$", var.image_uri))
    error_message = "Use the existing project image pinned by digest."
  }
}
variable "site_example_json" { type = string }
variable "verification_script" {
  description = "Shared standard-library HTTP verifier, read from the repository by Terragrunt."
  type        = string
}
variable "verification_run_id" { type = string }
variable "tags" { type = map(string) }
