# Reuse the cluster's existing IRSA provider. Only the named application service
# account can obtain these temporary credentials; worker and UI roles gain none.
resource "aws_iam_role" "risk" {
  name                 = "${var.cluster_name}-risk-service"
  permissions_boundary = var.role_boundaries["risk"]
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = aws_iam_openid_connect_provider.cluster.arn }
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")}:aud" = "sts.amazonaws.com"
          "${replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")}:sub" = "system:serviceaccount:clinical-trial-site-risk-monitor-demo:clinical-trial-risk-service"
        }
      }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "bedrock" {
  name = "explain-risk-with-nova-micro"
  role = aws_iam_role.risk.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "bedrock:InvokeModel"
      Resource  = "arn:aws:bedrock:us-east-1::foundation-model/amazon.nova-micro-v1:0"
      Condition = { StringEquals = { "aws:RequestedRegion" = "us-east-1" } }
    }]
  })
}

output "risk_service_role_arn" {
  description = "Application IRSA role; restricted to the named risk-service account and Nova Micro."
  value       = aws_iam_role.risk.arn
  sensitive   = true
}
