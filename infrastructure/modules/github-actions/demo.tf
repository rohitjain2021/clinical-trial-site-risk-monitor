locals {
  demo_cluster_name = "clinical-trial-site-risk-monitor-dev-eks"
  demo_cluster_arn  = "arn:aws:eks:${local.region}:${local.account_id}:cluster/${local.demo_cluster_name}"
  demo_role_arns = {
    cluster = "arn:aws:iam::${local.account_id}:role/${local.demo_cluster_name}-control-plane"
    nodes   = "arn:aws:iam::${local.account_id}:role/${local.demo_cluster_name}-nodes"
    cni     = "arn:aws:iam::${local.account_id}:role/${local.demo_cluster_name}-vpc-cni"
  }
  demo_boundaries = {
    cluster = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
    nodes   = "arn:aws:iam::${local.account_id}:policy/${local.demo_cluster_name}-nodes-boundary"
    cni     = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  }
  demo_oidc_arn = "arn:aws:iam::${local.account_id}:oidc-provider/oidc.eks.${local.region}.amazonaws.com/id/*"
  demo_eks_resources = [
    local.demo_cluster_arn,
    "arn:aws:eks:${local.region}:${local.account_id}:nodegroup/${local.demo_cluster_name}/${local.demo_cluster_name}-risk-nodes/*",
    "arn:aws:eks:${local.region}:${local.account_id}:addon/${local.demo_cluster_name}/*",
    "arn:aws:eks:${local.region}:${local.account_id}:access-entry/${local.demo_cluster_name}/*"
  ]
  demo_state_objects = [for unit in ["eks", "demo-app"] : "${local.state_bucket_arn}/dev/${unit}/terraform.tfstate"]
  # Nodes pull only the application and the documented AWS EKS system images.
  demo_image_resources = [
    local.ecr_repository_arn,
    "arn:aws:ecr:${local.region}:602401143452:repository/amazon-k8s-cni",
    "arn:aws:ecr:${local.region}:602401143452:repository/amazon-k8s-cni-init",
    "arn:aws:ecr:${local.region}:602401143452:repository/eks/kube-proxy",
    "arn:aws:ecr:${local.region}:602401143452:repository/eks/coredns"
  ]
}

data "aws_iam_policy" "worker" {
  arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# The demo workflow cannot edit this operator-managed permissions boundary.
resource "aws_iam_policy" "demo_nodes_boundary" {
  name = "${local.demo_cluster_name}-nodes-boundary"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(jsondecode(data.aws_iam_policy.worker.policy).Statement, [
      { Effect = "Allow", Action = "ecr:GetAuthorizationToken", Resource = "*", Condition = { StringEquals = { "aws:RequestedRegion" = local.region } } },
      { Effect = "Allow", Action = ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"], Resource = local.demo_image_resources }
    ])
  })
  tags = var.tags
}

resource "aws_iam_role" "demo" {
  name                 = "clinical-trial-site-risk-monitor-dev-github-demo"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow", Action = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Condition = { StringEquals = {
        "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        "token.actions.githubusercontent.com:sub" = local.trusted_subjects
      } }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "demo" {
  depends_on = [aws_iam_policy.demo_nodes_boundary]
  name       = "manage-dev-eks-demo"
  role       = aws_iam_role.demo.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      { Sid = "DiscoverState", Effect = "Allow", Action = "s3:ListBucket", Resource = local.state_bucket_arn },
      { Sid = "DemoState", Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject"], Resource = local.demo_state_objects },
      { Sid = "DemoLocks", Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], Resource = [for key in local.demo_state_objects : "${key}.tflock"] },
      # Dependencies are read-only; this role cannot change their infrastructure.
      { Sid = "ReadDependencies", Effect = "Allow", Action = "s3:GetObject", Resource = ["${local.state_bucket_arn}/dev/ecr/terraform.tfstate"] },
      { Sid = "InspectPublishedImage", Effect = "Allow", Action = "ecr:DescribeImages", Resource = local.ecr_repository_arn },
      {
        Sid      = "DiscoverRegionalInputs", Effect = "Allow"
        Action   = ["ec2:DescribeVpcs", "ec2:DescribeVpcAttribute", "ec2:DescribeRouteTables", "ec2:DescribeSubnets", "ec2:DescribeInstances", "ec2:DescribeVolumes", "ec2:DescribeLaunchTemplates", "ec2:DescribeLaunchTemplateVersions", "eks:DescribeAddonVersions", "logs:DescribeLogGroups"]
        Resource = "*", Condition = { StringEquals = { "aws:RequestedRegion" = local.region } }
      },
      {
        # EKS CreateCluster has no resource-level authorization; constrain its inputs.
        Sid = "CreateTaggedDemoCluster", Effect = "Allow", Action = "eks:CreateCluster", Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion"        = local.region
            "aws:RequestTag/Project"     = "clinical-trial-site-risk-monitor"
            "aws:RequestTag/Environment" = "dev"
            "aws:RequestTag/Name"        = local.demo_cluster_name
            "eks:authenticationMode"     = "API"
            "eks:supportType"            = "STANDARD"
            "eks:kubernetesVersion"      = "1.36"
          }
          Bool = {
            "eks:bootstrapClusterCreatorAdminPermissions" = "false"
            "eks:endpointPrivateAccess"                   = "true"
            "eks:endpointPublicAccess"                    = "true"
          }
        }
      },
      {
        Sid = "ManageOneCluster", Effect = "Allow"
        Action = [
          "eks:DescribeCluster", "eks:UpdateClusterConfig", "eks:UpdateClusterVersion", "eks:DeleteCluster",
          "eks:CreateNodegroup", "eks:DescribeNodegroup", "eks:UpdateNodegroupConfig", "eks:UpdateNodegroupVersion", "eks:DeleteNodegroup",
          "eks:CreateAddon", "eks:DescribeAddon", "eks:UpdateAddon", "eks:DeleteAddon",
          "eks:CreateAccessEntry", "eks:DescribeAccessEntry", "eks:UpdateAccessEntry", "eks:DeleteAccessEntry",
          "eks:AssociateAccessPolicy", "eks:DisassociateAccessPolicy", "eks:ListAssociatedAccessPolicies",
          "eks:ListTagsForResource", "eks:TagResource", "eks:UntagResource", "eks:DescribeUpdate"
        ]
        Resource = local.demo_eks_resources
      },
      {
        # Before the role exists, IAM authorizes GetRole against the pathless ARN.
        # Keep both exact forms so EKS can check absence and then create its SLR.
        Sid = "ReadEksNodegroupServiceRole", Effect = "Allow", Action = "iam:GetRole"
        Resource = [
          "arn:aws:iam::${local.account_id}:role/AWSServiceRoleForAmazonEKSNodegroup",
          "arn:aws:iam::${local.account_id}:role/aws-service-role/eks-nodegroup.amazonaws.com/AWSServiceRoleForAmazonEKSNodegroup"
        ]
      },
      {
        Sid      = "ManageDemoRoles", Effect = "Allow"
        Action   = ["iam:GetRole", "iam:DeleteRole", "iam:UpdateAssumeRolePolicy", "iam:TagRole", "iam:UntagRole", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole", "iam:GetRolePolicy", "iam:PutRolePolicy", "iam:DeleteRolePolicy"]
        Resource = values(local.demo_role_arns)
      },
      {
        Sid       = "AttachServicePolicies", Effect = "Allow", Action = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"]
        Resource  = values(local.demo_role_arns)
        Condition = { ArnEquals = { "iam:PolicyARN" = ["arn:aws:iam::aws:policy/AmazonEKSClusterPolicy", "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy", "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"] } }
      },
      {
        Sid       = "PassDemoRoles", Effect = "Allow", Action = "iam:PassRole", Resource = values(local.demo_role_arns)
        Condition = { StringEquals = { "iam:PassedToService" = ["eks.amazonaws.com", "ec2.amazonaws.com"] } }
      },
      {
        Sid       = "CreateClusterIdentity", Effect = "Allow", Action = ["iam:CreateOpenIDConnectProvider", "iam:TagOpenIDConnectProvider"]
        Resource  = local.demo_oidc_arn
        Condition = { StringEquals = { "aws:RequestTag/Project" = "clinical-trial-site-risk-monitor", "aws:RequestTag/Environment" = "dev", "aws:RequestTag/Name" = "${local.demo_cluster_name}-oidc" } }
      },
      {
        Sid = "ReadClusterIdentity", Effect = "Allow", Action = "iam:GetOpenIDConnectProvider", Resource = local.demo_oidc_arn
      },
      {
        Sid       = "ManageTaggedClusterIdentity", Effect = "Allow"
        Action    = ["iam:DeleteOpenIDConnectProvider", "iam:UpdateOpenIDConnectProviderThumbprint", "iam:AddClientIDToOpenIDConnectProvider", "iam:RemoveClientIDFromOpenIDConnectProvider", "iam:UntagOpenIDConnectProvider"]
        Resource  = local.demo_oidc_arn
        Condition = { StringEquals = { "aws:ResourceTag/Project" = "clinical-trial-site-risk-monitor", "aws:ResourceTag/Environment" = "dev", "aws:ResourceTag/Name" = "${local.demo_cluster_name}-oidc" } }
      },
      {
        Sid       = "CreateTaggedLaunchTemplate", Effect = "Allow", Action = "ec2:CreateLaunchTemplate"
        Resource  = "arn:aws:ec2:${local.region}:${local.account_id}:launch-template/*"
        Condition = { StringEquals = { "aws:RequestTag/Project" = "clinical-trial-site-risk-monitor", "aws:RequestTag/Environment" = "dev", "aws:RequestTag/Name" = "${local.demo_cluster_name}-nodes" } }
      },
      {
        Sid       = "TagNewLaunchTemplate", Effect = "Allow", Action = "ec2:CreateTags"
        Resource  = "arn:aws:ec2:${local.region}:${local.account_id}:launch-template/*"
        Condition = { StringEquals = { "ec2:CreateAction" = "CreateLaunchTemplate" } }
      },
      {
        Sid       = "ManageTaggedLaunchTemplate", Effect = "Allow"
        Action    = ["ec2:CreateLaunchTemplateVersion", "ec2:ModifyLaunchTemplate", "ec2:DeleteLaunchTemplateVersions", "ec2:DeleteLaunchTemplate", "ec2:CreateTags", "ec2:DeleteTags"]
        Resource  = "arn:aws:ec2:${local.region}:${local.account_id}:launch-template/*"
        Condition = { StringEquals = { "aws:ResourceTag/Project" = "clinical-trial-site-risk-monitor", "aws:ResourceTag/Environment" = "dev", "aws:ResourceTag/Name" = "${local.demo_cluster_name}-nodes" } }
      },
      {
        Sid      = "ManageClusterLogs", Effect = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy", "logs:DeleteRetentionPolicy", "logs:ListTagsForResource", "logs:TagResource", "logs:UntagResource"]
        Resource = ["arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/eks/${local.demo_cluster_name}/cluster", "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/eks/${local.demo_cluster_name}/cluster:*"]
      },
      {
        Sid       = "CreateEksServiceLinkedRoles", Effect = "Allow", Action = "iam:CreateServiceLinkedRole"
        Resource  = ["arn:aws:iam::${local.account_id}:role/aws-service-role/eks.amazonaws.com/*", "arn:aws:iam::${local.account_id}:role/aws-service-role/eks-nodegroup.amazonaws.com/*", "arn:aws:iam::${local.account_id}:role/aws-service-role/spot.amazonaws.com/*", "arn:aws:iam::${local.account_id}:role/aws-service-role/autoscaling.amazonaws.com/*"]
        Condition = { StringEquals = { "iam:AWSServiceName" = ["eks.amazonaws.com", "eks-nodegroup.amazonaws.com", "spot.amazonaws.com", "autoscaling.amazonaws.com"] } }
      }
      ], [for key, role in local.demo_role_arns : {
        Sid       = "CreateBounded${title(key)}Role", Effect = "Allow", Action = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"], Resource = role
        Condition = { StringEquals = { "iam:PermissionsBoundary" = local.demo_boundaries[key] } }
    }])
  })
}

output "demo_role_arn" {
  description = "Main-only GitHub OIDC role for the disposable EKS demo."
  value       = aws_iam_role.demo.arn
  sensitive   = true
}

output "demo_role_boundaries" {
  description = "Operator-managed boundaries required for demo-created EKS roles."
  value       = local.demo_boundaries
  sensitive   = true
}
