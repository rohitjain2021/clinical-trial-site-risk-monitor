output "api_base_url" {
  description = "Private ALB URL for later Lambda integration; keep outside public docs."
  value       = "http://${aws_lb.risk.dns_name}"
  sensitive   = true
}
output "client_security_group_id" {
  description = "Dedicated group to attach to Lambda during the next integration step."
  value       = aws_security_group.client.id
  sensitive   = true
}
output "target_group_arn" {
  description = "Private target group for health verification and operator inspection."
  value       = aws_lb_target_group.risk.arn
  sensitive   = true
}
