mock_provider "aws" {
  mock_resource "aws_lb" {
    defaults = {
      arn      = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/clinical-trial-risk-dev-alb/0123456789abcdef"
      dns_name = "example.internal"
    }
  }
  mock_resource "aws_lb_target_group" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/clinical-trial-risk-dev-tg/0123456789abcdef" }
  }
}
mock_provider "kubernetes" {}

override_resource {
  target = aws_security_group.alb
  values = { id = "sg-aaaaaaaaaaaaaaaaa" }
}
override_resource {
  target = aws_security_group.client
  values = { id = "sg-bbbbbbbbbbbbbbbbb" }
}

variables {
  vpc_id                        = "vpc-0123456789abcdef0"
  subnet_ids                    = ["subnet-0123456789abcdef0", "subnet-1123456789abcdef0"]
  worker_security_group_id      = "sg-ccccccccccccccccc"
  worker_autoscaling_group_name = "eks-clinical-trial-site-risk-monitor-dev-eks-risk-nodes-example"
  node_port                     = 30800
  cluster_name                  = "example-cluster"
  cluster_endpoint              = "https://example.invalid"
  cluster_certificate           = "ZXhhbXBsZQ=="
  namespace                     = "clinical-trial-site-risk-monitor-demo"
  image_uri                     = "123456789012.dkr.ecr.us-east-1.amazonaws.com/clinical-trial-site-risk-monitor-dev-risk-service@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  site_example_json             = "{}"
  verification_script           = "print('test')"
  verification_run_id           = "test"
  tags                          = { Project = "clinical-trial-site-risk-monitor", Environment = "dev", ManagedBy = "Terraform-Terragrunt" }
}

run "private_scoped_alb" {
  command = apply
  assert {
    condition     = aws_lb.risk.internal && aws_lb.risk.load_balancer_type == "application" && aws_lb.risk.drop_invalid_header_fields && toset(aws_lb.risk.subnets) == toset(var.subnet_ids)
    error_message = "Keep the ALB internal and reuse only the existing EKS subnets."
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.clients["workload"].referenced_security_group_id == var.worker_security_group_id && aws_vpc_security_group_ingress_rule.clients["lambda"].referenced_security_group_id == aws_security_group.client.id && aws_vpc_security_group_ingress_rule.clients["lambda"].cidr_ipv4 == null && aws_vpc_security_group_ingress_rule.clients["workload"].from_port == 80
    error_message = "Allow ALB requests only from the EKS and dedicated client security groups."
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.nodeport.security_group_id == var.worker_security_group_id && aws_vpc_security_group_ingress_rule.nodeport.referenced_security_group_id == aws_security_group.alb.id && aws_vpc_security_group_ingress_rule.nodeport.from_port == 30800 && aws_vpc_security_group_ingress_rule.nodeport.to_port == 30800 && aws_vpc_security_group_egress_rule.to_workers.referenced_security_group_id == var.worker_security_group_id && aws_vpc_security_group_egress_rule.client.referenced_security_group_id == aws_security_group.alb.id
    error_message = "Restrict backend ingress and ALB/client egress to their exact security groups and ports."
  }
  assert {
    condition     = aws_lb_target_group.risk.target_type == "instance" && aws_lb_target_group.risk.port == 30800 && aws_lb_target_group.risk.health_check[0].path == "/health" && aws_lb_target_group.risk.health_check[0].matcher == "200" && aws_autoscaling_traffic_source_attachment.workers.autoscaling_group_name == var.worker_autoscaling_group_name && aws_autoscaling_traffic_source_attachment.workers.traffic_source[0].identifier == aws_lb_target_group.risk.arn
    error_message = "Register replacement workers automatically and check FastAPI health on its fixed NodePort."
  }
  assert {
    condition     = kubernetes_job_v1.verify_alb.wait_for_completion && kubernetes_job_v1.verify_alb.spec[0].template[0].metadata[0].labels["app.kubernetes.io/name"] != "clinical-trial-risk-service" && !kubernetes_job_v1.verify_alb.spec[0].template[0].spec[0].automount_service_account_token && kubernetes_job_v1.verify_alb.spec[0].template[0].spec[0].container[0].security_context[0].read_only_root_filesystem
    error_message = "Gate ALB deployment on a hardened, isolated in-cluster HTTP verification job."
  }
}

run "reject_other_worker_group" {
  command = plan
  variables { worker_autoscaling_group_name = "unrelated-group" }
  expect_failures = [var.worker_autoscaling_group_name]
}

run "reject_other_node_port" {
  command = plan
  variables { node_port = 30001 }
  expect_failures = [var.node_port]
}
