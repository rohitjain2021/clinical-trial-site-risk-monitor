output "namespace" {
  description = "Existing application namespace for private ALB verification."
  value       = kubernetes_namespace_v1.demo.metadata[0].name
}

output "image_uri" {
  description = "Verified digest-pinned image reused by the ALB test job."
  value       = var.image_uri
  sensitive   = true
}

output "node_port" {
  description = "Stable worker port reached only through scoped security-group rules."
  value       = kubernetes_service_v1.risk.spec[0].port[0].node_port
}
