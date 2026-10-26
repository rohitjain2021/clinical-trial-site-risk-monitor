# EKS validates a custom node launch template with EC2 RunInstances using the
# caller's permissions. These permissions are distinct from the node IAM role.
data "aws_vpc" "demo_network" {
  default = true
}

data "aws_subnets" "demo_network" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.demo_network.id]
  }
  filter {
    name   = "availability-zone"
    values = ["us-east-1a", "us-east-1b"]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

locals {
  demo_template_arn = "arn:aws:ec2:${local.region}:${local.account_id}:launch-template/*"
}

# Keep launch permissions in a separate managed policy to stay within IAM's
# aggregate inline-policy size limit. Only the operator stack can edit it.
resource "aws_iam_policy" "demo_node_launch" {
  name = "clinical-trial-site-risk-monitor-dev-demo-node-launch"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "LaunchInputsInExistingDemoSubnets", Effect = "Allow", Action = "ec2:RunInstances"
        Resource = concat([
          "arn:aws:ec2:${local.region}::image/*",
          "arn:aws:ec2:${local.region}:${local.account_id}:security-group/*",
          "arn:aws:ec2:${local.region}:${local.account_id}:network-interface/*",
          "arn:aws:ec2:${local.region}:${local.account_id}:volume/*",
          "arn:aws:ec2:${local.region}:${local.account_id}:spot-instances-request/*"
        ], [for id in data.aws_subnets.demo_network.ids : "arn:aws:ec2:${local.region}:${local.account_id}:subnet/${id}"])
        Condition = { ArnLike = { "ec2:LaunchTemplate" = local.demo_template_arn } }
      },
      {
        Sid      = "LaunchSmallDemoWorkers", Effect = "Allow", Action = "ec2:RunInstances"
        Resource = "arn:aws:ec2:${local.region}:${local.account_id}:instance/*"
        Condition = {
          ArnLike      = { "ec2:LaunchTemplate" = local.demo_template_arn }
          StringEquals = { "ec2:InstanceType" = "t3.medium" }
        }
      },
      {
        Sid      = "UseOnlyTaggedDemoTemplate", Effect = "Allow", Action = "ec2:RunInstances"
        Resource = local.demo_template_arn
        Condition = { StringEquals = {
          "aws:ResourceTag/Project"     = "clinical-trial-site-risk-monitor"
          "aws:ResourceTag/Environment" = "dev"
          "aws:ResourceTag/Name"        = "${local.demo_cluster_name}-nodes"
        } }
      },
      {
        Sid      = "TagDemoInstancesAndDisksOnLaunch", Effect = "Allow", Action = "ec2:CreateTags"
        Resource = ["arn:aws:ec2:${local.region}:${local.account_id}:instance/*", "arn:aws:ec2:${local.region}:${local.account_id}:volume/*"]
        Condition = { StringEquals = {
          "ec2:CreateAction"           = "RunInstances"
          "aws:RequestTag/Project"     = "clinical-trial-site-risk-monitor"
          "aws:RequestTag/Environment" = "dev"
        } }
      }
    ]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "demo_node_launch" {
  role       = aws_iam_role.demo.name
  policy_arn = aws_iam_policy.demo_node_launch.arn
}
