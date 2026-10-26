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
