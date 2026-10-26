terraform {
  required_version = ">= 1.10.0, < 2.0.0"
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 3.0" }
  }
}

provider "kubernetes" {
  host                   = var.cluster_endpoint
  cluster_ca_certificate = base64decode(var.cluster_certificate)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", "us-east-1"]
  }
}

locals {
  name   = "clinical-trial-risk-service"
  labels = { "app.kubernetes.io/name" = "clinical-trial-risk-service", "app.kubernetes.io/part-of" = "clinical-trial-site-risk-monitor" }
  # The verification client must never become an HTTP Service endpoint.
  verification_labels = merge(local.labels, { "app.kubernetes.io/name" = "${local.name}-verification" })
}

resource "kubernetes_namespace_v1" "demo" {
  metadata {
    name   = "clinical-trial-site-risk-monitor-demo"
    labels = local.labels
  }
}

resource "kubernetes_deployment_v1" "risk" {
  metadata {
    name      = local.name
    namespace = kubernetes_namespace_v1.demo.metadata[0].name
    labels    = local.labels
  }
  spec {
    replicas = 1
    selector { match_labels = local.labels }
    template {
      metadata { labels = local.labels }
      spec {
        automount_service_account_token = false
        service_account_name            = kubernetes_service_account_v1.risk.metadata[0].name
        security_context {
          run_as_non_root = true
          run_as_user     = 10001
          run_as_group    = 10001
          seccomp_profile { type = "RuntimeDefault" }
        }
        container {
          name  = "risk-service"
          image = var.image_uri
          env {
            name  = "BEDROCK_ENABLED"
            value = "true"
          }
          env {
            name  = "AWS_DEFAULT_REGION"
            value = "us-east-1"
          }
          env {
            name  = "AWS_STS_REGIONAL_ENDPOINTS"
            value = "regional"
          }
          env {
            name  = "AWS_EC2_METADATA_DISABLED"
            value = "true"
          }
          port { container_port = 8000 }
          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities { drop = ["ALL"] }
          }
          resources {
            requests = { cpu = "100m", memory = "128Mi" }
            limits   = { cpu = "500m", memory = "256Mi" }
          }
          readiness_probe {
            http_get {
              path = "/health"
              port = 8000
            }
            period_seconds = 5
          }
          liveness_probe {
            http_get {
              path = "/health"
              port = 8000
            }
            initial_delay_seconds = 15
          }
        }
      }
    }
  }
  wait_for_rollout = true
  timeouts {
    create = "10m"
    update = "10m"
    delete = "5m"
  }
}

resource "kubernetes_service_account_v1" "risk" {
  metadata {
    name        = local.name
    namespace   = kubernetes_namespace_v1.demo.metadata[0].name
    labels      = local.labels
    annotations = { "eks.amazonaws.com/role-arn" = var.risk_service_role_arn }
  }
  automount_service_account_token = false
}

resource "kubernetes_service_v1" "risk" {
  metadata {
    name      = local.name
    namespace = kubernetes_namespace_v1.demo.metadata[0].name
    labels    = local.labels
  }
  spec {
    selector = local.labels
    type     = "NodePort"
    port {
      port        = 8000
      target_port = 8000
      node_port   = 30800
    }
  }
}

# A real in-cluster HTTP check gates deployment success, without exposing a public API.
resource "kubernetes_job_v1" "verify" {
  metadata {
    name      = "risk-service-verification"
    namespace = kubernetes_namespace_v1.demo.metadata[0].name
    labels    = local.verification_labels
  }
  spec {
    backoff_limit           = 0
    active_deadline_seconds = 120
    template {
      metadata { labels = local.verification_labels }
      spec {
        restart_policy                  = "Never"
        automount_service_account_token = false
        security_context {
          run_as_non_root = true
          run_as_user     = 10001
          run_as_group    = 10001
          seccomp_profile { type = "RuntimeDefault" }
        }
        container {
          name  = "verify"
          image = var.image_uri
          env {
            name  = "VERIFICATION_RUN_ID"
            value = var.verification_run_id
          }
          env {
            name  = "SITE_JSON"
            value = var.site_example_json
          }
          env {
            name  = "REQUIRE_EXPLANATION"
            value = "true"
          }
          command = ["python", "-c", file("${path.module}/verify.py")]
          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities { drop = ["ALL"] }
          }
          resources {
            requests = { cpu = "50m", memory = "64Mi" }
            limits   = { cpu = "100m", memory = "128Mi" }
          }
        }
      }
    }
  }
  wait_for_completion = true
  timeouts {
    create = "5m"
    delete = "5m"
  }
  depends_on = [kubernetes_deployment_v1.risk, kubernetes_service_v1.risk]
}
