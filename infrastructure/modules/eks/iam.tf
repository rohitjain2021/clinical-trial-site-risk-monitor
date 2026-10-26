# AWS service roles use only the service trust they require.
resource "aws_iam_role" "cluster" {
  permissions_boundary = var.role_boundaries["cluster"]
  name                 = "${var.cluster_name}-control-plane"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "eks.amazonaws.com" } }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "nodes" {
  permissions_boundary = var.role_boundaries["nodes"]
  name                 = "${var.cluster_name}-nodes"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ec2.amazonaws.com" } }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "nodes" {
  role       = aws_iam_role.nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy" "node_images" {
  name = "pull-risk-service-and-eks-system-images"
  role = aws_iam_role.nodes.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "ecr:GetAuthorizationToken"
        Resource  = "*"
        Condition = { StringEquals = { "aws:RequestedRegion" = "us-east-1" } }
      },
      {
        Effect = "Allow"
        Action = ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
        Resource = [
          "arn:aws:ecr:us-east-1:${data.aws_caller_identity.current.account_id}:repository/${var.image_repository_name}",
          # AWS's documented us-east-1 EKS add-on registry, not our account ID.
          "arn:aws:ecr:us-east-1:602401143452:repository/amazon-k8s-cni",
          "arn:aws:ecr:us-east-1:602401143452:repository/amazon-k8s-cni-init",
          "arn:aws:ecr:us-east-1:602401143452:repository/eks/kube-proxy",
          "arn:aws:ecr:us-east-1:602401143452:repository/eks/coredns"
        ]
      }
    ]
  })
}

# Only the aws-node service account can assume the separate networking role.
resource "aws_iam_openid_connect_provider" "cluster" {
  url            = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
  tags           = merge(var.tags, { Name = "${var.cluster_name}-oidc" })
}

resource "aws_iam_role" "cni" {
  permissions_boundary = var.role_boundaries["cni"]
  name                 = "${var.cluster_name}-vpc-cni"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = aws_iam_openid_connect_provider.cluster.arn }
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")}:aud" = "sts.amazonaws.com"
          "${replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-node"
        }
      }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cni" {
  role       = aws_iam_role.cni.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}
