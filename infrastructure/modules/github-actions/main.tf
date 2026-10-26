terraform {
  required_version = ">= 1.10.0, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "tags" {
  description = "Project and environment tags supplied by Terragrunt."
  type        = map(string)
  default     = {}
}

locals {
  account_id       = var.aws_account_id
  region           = "us-east-1"
  function_name    = "clinical-trial-site-risk-monitor-dev"
  function_arn     = "arn:aws:lambda:${local.region}:${local.account_id}:function:${local.function_name}"
  execution_role   = "arn:aws:iam::${local.account_id}:role/${local.function_name}-execution"
  log_group_arn    = "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/${local.function_name}"
  state_bucket_arn = "arn:aws:s3:::${var.state_bucket}"
  state_object_arn = "${local.state_bucket_arn}/dev/lambda/terraform.tfstate"
  # Support both GitHub subject formats, each restricted to this repository and main.
  trusted_subjects = [
    "repo:${var.github_repository}:ref:refs/heads/main",
    "repo:${split("/", var.github_repository)[0]}@${var.github_owner_id}/${split("/", var.github_repository)[1]}@${var.github_repository_id}:ref:refs/heads/main",
  ]
}

# AWS validates GitHub's certificate chain using its trusted CA library.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  tags           = var.tags
}

# CI can edit this Lambda role's inline policy, so a separately managed boundary
# prevents those edits from granting the running function broader AWS access.
resource "aws_iam_policy" "lambda_boundary" {
  name        = "clinical-trial-site-risk-monitor-dev-lambda-boundary"
  description = "Maximum permissions for the development Lambda execution role"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${local.log_group_arn}:log-stream:*"
      }, {
      Sid       = "LambdaServiceNetworking", Effect = "Allow"
      Action    = ["ec2:CreateNetworkInterface", "ec2:DescribeNetworkInterfaces", "ec2:DescribeSubnets", "ec2:DeleteNetworkInterface", "ec2:AssignPrivateIpAddresses", "ec2:UnassignPrivateIpAddresses"]
      Resource  = "*"
      Condition = { StringEquals = { "aws:RequestedRegion" = local.region } }
      }, {
      # AWS's SourceFunctionArn key distinguishes handler code from ENI service calls.
      Sid       = "DenyFunctionCodeNetworking", Effect = "Deny"
      Action    = ["ec2:CreateNetworkInterface", "ec2:DescribeNetworkInterfaces", "ec2:DescribeSubnets", "ec2:DeleteNetworkInterface", "ec2:AssignPrivateIpAddresses", "ec2:UnassignPrivateIpAddresses", "ec2:DetachNetworkInterface"]
      Resource  = "*"
      Condition = { ArnEquals = { "lambda:SourceFunctionArn" = local.function_arn } }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role" "deployment" {
  name                 = "clinical-trial-site-risk-monitor-dev-github-deploy"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = local.trusted_subjects
        }
      }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "deployment" {
  name = "deploy-dev-health-lambda"
  role = aws_iam_role.deployment.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "StateBucketDiscovery"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = local.state_bucket_arn
      },
      {
        Sid      = "LambdaStateOnly"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = local.state_object_arn
      },
      {
        Sid      = "LambdaStateLockOnly"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${local.state_object_arn}.tflock"
      },
      {
        Sid    = "ManageOneLambda"
        Effect = "Allow"
        Action = [
          "lambda:DeleteFunction", "lambda:GetFunction",
          "lambda:GetFunctionConfiguration", "lambda:GetFunctionCodeSigningConfig",
          "lambda:GetFunctionConcurrency", "lambda:GetRuntimeManagementConfig",
          "lambda:UpdateFunctionCode",
          "lambda:ListVersionsByFunction", "lambda:ListTags", "lambda:TagResource",
          "lambda:UntagResource", "lambda:InvokeFunction"
        ]
        Resource = local.function_arn
      },
      {
        Sid      = "ReadAlbDependency", Effect = "Allow", Action = "s3:GetObject"
        Resource = "${local.state_bucket_arn}/dev/alb/terraform.tfstate"
      },
      {
        Sid      = "DiscoverLambdaNetwork", Effect = "Allow"
        Action   = ["ec2:DescribeSecurityGroups", "ec2:DescribeSubnets", "ec2:DescribeVpcs", "ec2:GetSecurityGroupsForVpc"]
        Resource = "*", Condition = { StringEquals = { "aws:RequestedRegion" = local.region } }
      },
      {
        Sid    = "ConfigureLambdaInExistingNetwork", Effect = "Allow"
        Action = ["lambda:CreateFunction", "lambda:UpdateFunctionConfiguration"], Resource = local.function_arn
        # Missing VPC keys permit non-network updates and an explicit disconnect.
        Condition = {
          StringEqualsIfExists        = { "lambda:VpcIds" = data.aws_vpc.demo_network.id }
          "ForAllValues:StringEquals" = { "lambda:SubnetIds" = data.aws_subnets.demo_network.ids }
        }
      },
      {
        Sid      = "CreateBoundedExecutionRole"
        Effect   = "Allow"
        Action   = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"]
        Resource = local.execution_role
        Condition = {
          StringEquals = { "iam:PermissionsBoundary" = aws_iam_policy.lambda_boundary.arn }
        }
      },
      {
        Sid    = "ManageOneExecutionRole"
        Effect = "Allow"
        Action = [
          "iam:GetRole", "iam:DeleteRole", "iam:UpdateAssumeRolePolicy",
          "iam:TagRole", "iam:UntagRole", "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies", "iam:GetRolePolicy",
          "iam:PutRolePolicy", "iam:DeleteRolePolicy"
        ]
        Resource = local.execution_role
      },
      {
        Sid      = "PassOnlyLambdaExecutionRole"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = local.execution_role
        Condition = {
          StringEquals = { "iam:PassedToService" = "lambda.amazonaws.com" }
        }
      },
      {
        Sid    = "ManageOneLogGroup"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy",
          "logs:DeleteRetentionPolicy", "logs:ListTagsForResource",
          "logs:TagResource", "logs:UntagResource", "logs:DescribeLogStreams"
        ]
        Resource = [local.log_group_arn, "${local.log_group_arn}:*"]
      },
      {
        # DescribeLogGroups has no resource-level IAM support; limit it to the region.
        Sid       = "DiscoverLogGroupsInDevRegion"
        Effect    = "Allow"
        Action    = "logs:DescribeLogGroups"
        Resource  = "*"
        Condition = { StringEquals = { "aws:RequestedRegion" = local.region } }
      }
    ]
  })
}

output "deployment_role_arn" {
  description = "Role assumed by this repository's main-branch GitHub Actions jobs."
  value       = aws_iam_role.deployment.arn
}

output "lambda_boundary_arn" {
  description = "Required boundary when the pipeline creates the Lambda execution role."
  value       = aws_iam_policy.lambda_boundary.arn
}
