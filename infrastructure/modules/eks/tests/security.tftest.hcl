mock_provider "aws" {
  mock_resource "aws_launch_template" {
    defaults = { id = "lt-0123456789abcdef0", latest_version = 1 }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_vpc" {
    defaults = { id = "vpc-example", enable_dns_support = true, enable_dns_hostnames = true }
  }
  mock_data "aws_subnets" {
    defaults = { ids = ["subnet-a", "subnet-b"] }
  }
  mock_data "aws_eks_addon_version" {
    defaults = { version = "v1.0.0-eksbuild.1" }
  }
  mock_resource "aws_eks_cluster" {
    defaults = {
      certificate_authority = [{ data = "ZXhhbXBsZQ==" }]
      identity              = [{ oidc = [{ issuer = "https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE" }] }]
    }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/example-role" }
  }
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE" }
  }
}

override_data {
  target = data.aws_subnet.existing["subnet-a"]
  values = { availability_zone = "us-east-1a", availability_zone_id = "use1-az1", available_ip_address_count = 100, map_public_ip_on_launch = true }
}
override_data {
  target = data.aws_subnet.existing["subnet-b"]
  values = { availability_zone = "us-east-1b", availability_zone_id = "use1-az2", available_ip_address_count = 100, map_public_ip_on_launch = true }
}

variables {
  demo_principal_arn = "arn:aws:iam::123456789012:role/example-demo"
  role_boundaries = {
    cluster = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
    nodes   = "arn:aws:iam::123456789012:policy/example-nodes-boundary"
    cni     = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  }
  cluster_name          = "clinical-trial-site-risk-monitor-dev-eks"
  admin_principal_arn   = "arn:aws:iam::123456789012:role/example-operator"
  admin_cidrs           = ["203.0.113.10/32"]
  image_repository_name = "clinical-trial-site-risk-monitor-dev-risk-service"
  tags                  = { Project = "clinical-trial-site-risk-monitor", Environment = "dev", ManagedBy = "Terraform-Terragrunt" }
}

run "restricted_development_cluster" {
  command = apply

  assert {
    condition     = contains(jsondecode(aws_iam_role_policy.node_images.policy).Statement[1].Resource, "arn:aws:ecr:us-east-1:602401143452:repository/amazon/aws-network-policy-agent")
    error_message = "Workers must pull the exact network-policy agent image required by the VPC CNI add-on."
  }

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].endpoint_private_access && aws_eks_cluster.this.vpc_config[0].endpoint_public_access && toset(aws_eks_cluster.this.vpc_config[0].public_access_cidrs) == toset(var.admin_cidrs) && toset(aws_eks_cluster.this.vpc_config[0].subnet_ids) == toset(["subnet-a", "subnet-b"])
    error_message = "Reuse the selected existing subnets and restrict public API access to the operator."
  }
  assert {
    condition     = aws_eks_cluster.this.access_config[0].authentication_mode == "API" && !aws_eks_cluster.this.access_config[0].bootstrap_cluster_creator_admin_permissions && aws_eks_access_entry.operator.principal_arn == var.admin_principal_arn && aws_eks_cluster.this.upgrade_policy[0].support_type == "STANDARD"
    error_message = "Track operator access explicitly and keep standard version support."
  }
  assert {
    condition     = aws_launch_template.nodes.metadata_options[0].http_tokens == "required" && aws_launch_template.nodes.metadata_options[0].http_put_response_hop_limit == 1 && aws_launch_template.nodes.block_device_mappings[0].ebs[0].encrypted && aws_launch_template.nodes.block_device_mappings[0].ebs[0].delete_on_termination && aws_eks_node_group.risk.scaling_config[0].desired_size == 1 && aws_eks_node_group.risk.scaling_config[0].max_size == 1 && aws_eks_node_group.risk.capacity_type == "SPOT" && aws_eks_node_group.risk.update_config[0].update_strategy == "MINIMAL"
    error_message = "Require IMDSv2, encrypted disposable root disks, and bounded development capacity."
  }
  assert {
    condition     = jsondecode(aws_iam_role.cni.assume_role_policy).Statement[0].Condition.StringEquals["oidc.eks.us-east-1.amazonaws.com/id/EXAMPLE:sub"] == "system:serviceaccount:kube-system:aws-node" && aws_iam_role_policy_attachment.cni.role == aws_iam_role.cni.name && aws_iam_role_policy_attachment.nodes.policy_arn == "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy" && aws_eks_addon.core["vpc-cni"].service_account_role_arn == aws_iam_role.cni.arn
    error_message = "Isolate CNI networking permissions to its own service-account role."
  }
  assert {
    condition     = toset(jsondecode(aws_iam_role_policy.node_images.policy).Statement[1].Action) == toset(["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]) && contains(jsondecode(aws_iam_role_policy.node_images.policy).Statement[1].Resource, "arn:aws:ecr:us-east-1:123456789012:repository/clinical-trial-site-risk-monitor-dev-risk-service") && !contains(jsondecode(aws_iam_role_policy.node_images.policy).Statement[1].Resource, "*") && aws_cloudwatch_log_group.cluster.retention_in_days == 14
    error_message = "Nodes can pull only the application and named system images, with finite log retention."
  }
}

run "reject_open_api" {
  command = plan
  variables { admin_cidrs = ["0.0.0.0/0"] }
  expect_failures = [var.admin_cidrs]
}

run "reject_unsupported_zone" {
  command = plan
  override_data {
    target = data.aws_subnet.existing["subnet-b"]
    values = { availability_zone = "us-east-1b", availability_zone_id = "use1-az3", available_ip_address_count = 100, map_public_ip_on_launch = true }
  }
  expect_failures = [aws_eks_cluster.this]
}
