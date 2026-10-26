terraform {
  required_version = ">= 1.10.0, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

data "aws_caller_identity" "current" {}

# Read the shared default network; this stack must never own or delete it.
data "aws_vpc" "existing" {
  default = true
}

data "aws_subnets" "existing" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.existing.id]
  }
  filter {
    name   = "availability-zone"
    values = var.availability_zones
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

data "aws_subnet" "existing" {
  for_each = toset(data.aws_subnets.existing.ids)
  id       = each.value
}

locals {
  subnet_ids = sort(data.aws_subnets.existing.ids)
  addons     = toset(["vpc-cni", "kube-proxy", "coredns"])
}

resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 14
  tags              = var.tags
}

resource "aws_eks_cluster" "this" {
  name                      = var.cluster_name
  version                   = var.kubernetes_version
  role_arn                  = aws_iam_role.cluster.arn
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }

  # Standard support avoids silently opting into the extended-support price.
  upgrade_policy {
    support_type = "STANDARD"
  }

  vpc_config {
    subnet_ids              = local.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.admin_cidrs
  }

  lifecycle {
    precondition {
      condition     = length(local.subnet_ids) == 2 && length(toset([for s in data.aws_subnet.existing : s.availability_zone])) == 2
      error_message = "Select exactly two existing default subnets in different Availability Zones."
    }
    precondition {
      condition     = data.aws_vpc.existing.enable_dns_support && data.aws_vpc.existing.enable_dns_hostnames && alltrue([for s in data.aws_subnet.existing : s.availability_zone_id != "use1-az3" && s.available_ip_address_count >= 16 && s.map_public_ip_on_launch])
      error_message = "Require VPC DNS, supported EKS zones, at least 16 free subnet addresses, and public IPv4 assignment for these public worker subnets."
    }
  }

  tags       = merge(var.tags, { Name = var.cluster_name })
  depends_on = [aws_iam_role_policy_attachment.cluster, aws_cloudwatch_log_group.cluster]
}

# Explicit access is tracked in state, rather than an implicit creator-admin grant.
resource "aws_eks_access_entry" "operator" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.admin_principal_arn
  type          = "STANDARD"
  tags          = var.tags
}

resource "aws_eks_access_policy_association" "operator" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.operator.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
}

resource "aws_eks_access_entry" "demo" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.demo_principal_arn
  type          = "STANDARD"
  tags          = var.tags
}

resource "aws_eks_access_policy_association" "demo" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.demo.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope { type = "cluster" }
}

# Let EKS attach its project cluster security group; no SSH key or remote access.
resource "aws_launch_template" "nodes" {
  name = "${var.cluster_name}-nodes"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  # Bound burstable CPU use rather than incur unlimited-mode surplus charges.
  credit_specification {
    cpu_credits = "standard"
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "${var.cluster_name}-risk-node" })
  }
  tag_specifications {
    resource_type = "volume"
    tags          = merge(var.tags, { Name = "${var.cluster_name}-node-root" })
  }
  tags = merge(var.tags, { Name = "${var.cluster_name}-nodes" })
}

resource "aws_eks_node_group" "risk" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-risk-nodes"
  node_role_arn   = aws_iam_role.nodes.arn
  subnet_ids      = local.subnet_ids
  version         = var.kubernetes_version
  ami_type        = "AL2023_x86_64_STANDARD"
  capacity_type   = "SPOT"
  instance_types  = ["t3.medium"]

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 1
  }
  launch_template {
    id      = aws_launch_template.nodes.id
    version = tostring(aws_launch_template.nodes.latest_version)
  }
  update_config {
    max_unavailable = 1
    update_strategy = "MINIMAL"
  }

  tags = merge(var.tags, { Name = "${var.cluster_name}-risk-nodes" })
  # CNI and nodes can converge in parallel; do not make add-on readiness a cycle.
  depends_on = [aws_iam_role_policy_attachment.nodes, aws_iam_role_policy.node_images, aws_iam_role_policy_attachment.cni]
}

data "aws_eks_addon_version" "compatible" {
  for_each           = local.addons
  addon_name         = each.value
  kubernetes_version = var.kubernetes_version
  most_recent        = true
}

resource "aws_eks_addon" "core" {
  for_each                    = local.addons
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.value
  addon_version               = data.aws_eks_addon_version.compatible[each.key].version
  service_account_role_arn    = each.key == "vpc-cni" ? aws_iam_role.cni.arn : null
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  tags                        = var.tags
  depends_on                  = [aws_iam_role_policy_attachment.cni]
}
