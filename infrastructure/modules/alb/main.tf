terraform {
  required_version = ">= 1.10.0, < 2.0.0"
  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 6.0" }
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
  project = "clinical-trial-site-risk-monitor-dev"
}

# Rules are separate resources so the two dedicated groups do not form a cycle.
resource "aws_security_group" "alb" {
  name        = "${local.project}-alb"
  description = "Private risk-service ALB; only EKS checks and the future Lambda client"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${local.project}-alb" })
}

resource "aws_security_group" "client" {
  name        = "${local.project}-alb-client"
  description = "Dedicated outbound-only ALB client group for future Lambda integration"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${local.project}-alb-client" })
}

resource "aws_vpc_security_group_ingress_rule" "clients" {
  for_each                     = { workload = var.worker_security_group_id, lambda = aws_security_group.client.id }
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  description                  = "Private HTTP from ${each.key} only"
  tags                         = var.tags
}

resource "aws_vpc_security_group_egress_rule" "to_workers" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = var.worker_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.node_port
  to_port                      = var.node_port
  description                  = "ALB forwarding and health checks to the risk-service NodePort"
  tags                         = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "nodeport" {
  security_group_id            = var.worker_security_group_id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.node_port
  to_port                      = var.node_port
  description                  = "Risk-service NodePort from the private ALB only"
  tags                         = var.tags
}

resource "aws_vpc_security_group_egress_rule" "client" {
  security_group_id            = aws_security_group.client.id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  description                  = "Future Lambda client to the private ALB only"
  tags                         = var.tags
}

resource "aws_lb" "risk" {
  name                       = "clinical-trial-risk-dev-alb"
  internal                   = true
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = var.subnet_ids
  drop_invalid_header_fields = true
  idle_timeout               = 30
  enable_deletion_protection = false
  tags                       = merge(var.tags, { Name = "${local.project}-alb" })
}

resource "aws_lb_target_group" "risk" {
  name                 = "clinical-trial-risk-dev-tg"
  port                 = var.node_port
  protocol             = "HTTP"
  target_type          = "instance"
  vpc_id               = var.vpc_id
  deregistration_delay = 30
  health_check {
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 15
    timeout             = 5
  }
  tags = merge(var.tags, { Name = "${local.project}-risk-targets" })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.risk.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.risk.arn
  }
  tags = var.tags
}

# Auto Scaling registers replacement workers; Terraform never pins an instance IP.
# This resource owns only the attachment, not the EKS-managed Auto Scaling group.
resource "aws_autoscaling_traffic_source_attachment" "workers" {
  autoscaling_group_name = var.worker_autoscaling_group_name
  traffic_source {
    identifier = aws_lb_target_group.risk.arn
    type       = "elbv2"
  }
  depends_on = [aws_lb_listener.http]
}

resource "kubernetes_job_v1" "verify_alb" {
  metadata {
    name      = "risk-alb-verification"
    namespace = var.namespace
    labels    = { "app.kubernetes.io/name" = "risk-alb-verification", "app.kubernetes.io/part-of" = "clinical-trial-site-risk-monitor" }
  }
  spec {
    backoff_limit           = 0
    active_deadline_seconds = 180
    template {
      metadata { labels = { "app.kubernetes.io/name" = "risk-alb-verification" } }
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
          name    = "verify"
          image   = var.image_uri
          command = ["python", "-c", var.verification_script]
          env {
            name  = "API_BASE_URL"
            value = sensitive("http://${aws_lb.risk.dns_name}")
          }
          env {
            name  = "SITE_JSON"
            value = var.site_example_json
          }
          env {
            name  = "HEALTH_ATTEMPTS"
            value = "24"
          }
          env {
            name  = "VERIFICATION_RUN_ID"
            value = var.verification_run_id
          }
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
  depends_on = [
    aws_lb_listener.http,
    aws_autoscaling_traffic_source_attachment.workers,
    aws_vpc_security_group_ingress_rule.clients,
    aws_vpc_security_group_ingress_rule.nodeport,
    aws_vpc_security_group_egress_rule.to_workers,
  ]
}
