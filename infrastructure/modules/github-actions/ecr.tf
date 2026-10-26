variable "ecr_repository_name" {
  description = "Existing project repository; CI can publish images but cannot manage the repository."
  type        = string
}

locals {
  ecr_repository_arn = "arn:aws:ecr:${local.region}:${local.account_id}:repository/${var.ecr_repository_name}"
}

# Operator-managed permissions let main-branch OIDC publish only the risk image.
resource "aws_iam_role_policy" "image_publish" {
  name = "publish-dev-risk-service-image"
  role = aws_iam_role.deployment.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # ECR authentication has no resource-level IAM support.
        Sid       = "RegistryLoginInDevRegion"
        Effect    = "Allow"
        Action    = "ecr:GetAuthorizationToken"
        Resource  = "*"
        Condition = { StringEquals = { "aws:RequestedRegion" = local.region } }
      },
      {
        Sid    = "PublishOneRiskServiceImage"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage",
          "ecr:BatchGetImage", "ecr:DescribeImages"
        ]
        Resource = local.ecr_repository_arn
      }
    ]
  })
}
