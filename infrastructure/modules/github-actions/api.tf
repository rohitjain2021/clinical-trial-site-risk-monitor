variable "api_gateway_id" {
  description = "Existing project API ID; CI manages only this API after operator bootstrap."
  type        = string
  default     = null
}

locals {
  api_log_group_arn = "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/apigateway/${local.function_name}"
  api_arn           = "arn:aws:apigateway:${local.region}::/apis/${coalesce(var.api_gateway_id, "not-provisioned")}"
}

# Operator-managed delivery policy avoids giving CI logs:PutResourcePolicy on the account.
resource "aws_cloudwatch_log_resource_policy" "api" {
  policy_name = "clinical-trial-site-risk-monitor-dev-api-access"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "delivery.logs.amazonaws.com" }
      Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource  = "${local.api_log_group_arn}:log-stream:*"
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:aws:logs:${local.region}:${local.account_id}:*" }
      }
    }]
  })
}

resource "aws_iam_role_policy" "api_logs" {
  name = "manage-dev-api-access-logs"
  role = aws_iam_role.deployment.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy",
          "logs:DeleteRetentionPolicy", "logs:ListTagsForResource", "logs:TagResource", "logs:UntagResource"
        ]
        Resource = [local.api_log_group_arn, "${local.api_log_group_arn}:*"]
      },
      {
        # These delivery/discovery APIs lack resource-level authorization support.
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery", "logs:GetLogDelivery", "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery", "logs:ListLogDeliveries", "logs:DescribeResourcePolicies"
        ]
        Resource  = "*"
        Condition = { StringEquals = { "aws:RequestedRegion" = local.region } }
      }
    ]
  })
}

# Initial API creation is operator-run Terraform. CI has no API collection access.
# A replacement API requires the operator to refresh this ID and policy explicitly.
resource "aws_iam_role_policy" "api" {
  count = var.api_gateway_id == null ? 0 : 1
  name  = "manage-project-api"
  role  = aws_iam_role.deployment.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["apigateway:GET", "apigateway:POST", "apigateway:PATCH", "apigateway:PUT", "apigateway:DELETE"]
        Resource = [
          local.api_arn, "${local.api_arn}/*",
          "arn:aws:apigateway:${local.region}::/tags/${local.api_arn}",
          "arn:aws:apigateway:${local.region}::/tags/${local.api_arn}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["lambda:GetPolicy", "lambda:RemovePermission"]
        Resource = local.function_arn
      },
      {
        Effect    = "Allow"
        Action    = "lambda:AddPermission"
        Resource  = local.function_arn
        Condition = { StringEquals = { "lambda:Principal" = "apigateway.amazonaws.com" } }
      },
      {
        Effect = "Allow"
        Action = "execute-api:Invoke"
        Resource = [
          "arn:aws:execute-api:${local.region}:${local.account_id}:${var.api_gateway_id}/dev/GET/health",
          "arn:aws:execute-api:${local.region}:${local.account_id}:${var.api_gateway_id}/dev/POST/site-assessments"
        ]
      }
    ]
  })
}
