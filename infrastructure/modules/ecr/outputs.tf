output "repository_name" {
  description = "Project-specific name of the private risk-service repository."
  value       = aws_ecr_repository.this.name
}

output "repository_arn" {
  description = "Repository ARN for future scoped image-publishing and pull permissions."
  value       = aws_ecr_repository.this.arn
  sensitive   = true
}

output "repository_url" {
  description = "Private repository URL for future image publishing and EKS deployment."
  value       = aws_ecr_repository.this.repository_url
  sensitive   = true
}
