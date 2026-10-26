output "cluster_name" {
  description = "Project-specific cluster name for later operator access."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Restricted Kubernetes API endpoint; keep out of public documentation."
  value       = aws_eks_cluster.this.endpoint
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "EKS-owned security group for future scoped load-balancer integration."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  sensitive   = true
}

output "cluster_certificate" {
  description = "Cluster CA needed by the separate Terraform application unit."
  value       = aws_eks_cluster.this.certificate_authority[0].data
  sensitive   = true
}

output "vpc_id" {
  description = "Existing VPC used by EKS and the private ALB."
  value       = data.aws_vpc.existing.id
  sensitive   = true
}

output "subnet_ids" {
  description = "Existing subnets for the private ALB; no shared network ownership."
  value       = local.subnet_ids
  sensitive   = true
}

output "worker_autoscaling_group_name" {
  description = "EKS-managed worker group for automatic ALB target registration."
  value       = one(aws_eks_node_group.risk.resources[0].autoscaling_groups).name
  sensitive   = true
}
