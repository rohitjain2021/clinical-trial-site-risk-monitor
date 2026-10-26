locals {
  notification_topic_arn = "arn:aws:sns:us-east-1:${data.aws_caller_identity.current.account_id}:clinical-trial-site-risk-monitor-dev-assessments"
}

resource "aws_iam_role_policy" "notifications" {
  name = "publish-assessment-notifications"
  role = aws_iam_role.risk.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sns:Publish"
      Resource  = local.notification_topic_arn
      Condition = { StringEquals = { "aws:RequestedRegion" = "us-east-1" } }
    }]
  })
}

output "assessment_notification_topic_arn" {
  description = "Exact project topic provisioned by the separate operator notification unit."
  value       = local.notification_topic_arn
  sensitive   = true
}
