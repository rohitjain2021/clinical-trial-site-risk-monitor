mock_provider "aws" {
  override_during = plan
  mock_resource "aws_sns_topic" {
    defaults = { arn = "arn:aws:sns:us-east-1:123456789012:clinical-trial-site-risk-monitor-dev-assessments" }
  }
}

variables { email = "demo@example.com" }

run "one_private_email_topic" {
  command = plan
  assert {
    condition     = aws_sns_topic.assessments.name == "clinical-trial-site-risk-monitor-dev-assessments" && !aws_sns_topic.assessments.fifo_topic && aws_sns_topic_subscription.email.protocol == "email" && aws_sns_topic_subscription.email.endpoint == var.email && !aws_sns_topic_subscription.email.endpoint_auto_confirms
    error_message = "Use one project standard topic and require the recipient to confirm email delivery."
  }
  assert {
    condition     = length(jsondecode(aws_sns_topic_policy.transport.policy).Statement) == 1 && jsondecode(aws_sns_topic_policy.transport.policy).Statement[0].Effect == "Deny" && jsondecode(aws_sns_topic_policy.transport.policy).Statement[0].Action == "sns:Publish" && jsondecode(aws_sns_topic_policy.transport.policy).Statement[0].Condition.Bool["aws:SecureTransport"] == "false"
    error_message = "The resource policy must deny insecure publishing and grant no public access."
  }
}

run "reject_invalid_recipient" {
  command = plan
  variables { email = "not-an-address" }
  expect_failures = [var.email]
}
