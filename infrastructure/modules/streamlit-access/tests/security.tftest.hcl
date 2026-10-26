mock_provider "aws" {
  override_during = plan
  mock_resource "aws_iam_policy" {
    defaults = { arn = "arn:aws:iam::123456789012:policy/clinical-trial-site-risk-monitor-dev-streamlit-boundary" }
  }
}

run "assessment_only" {
  command = plan
  variables {
    api_execution_arn = "arn:aws:execute-api:us-east-1:123456789012:exampleapi"
  }
  assert {
    condition     = jsondecode(aws_iam_user_policy.invoke.policy).Statement == jsondecode(aws_iam_policy.boundary.policy).Statement && jsondecode(aws_iam_user_policy.invoke.policy).Statement[0].Action == "execute-api:Invoke" && jsondecode(aws_iam_user_policy.invoke.policy).Statement[0].Resource == "arn:aws:execute-api:us-east-1:123456789012:exampleapi/dev/POST/site-assessments"
    error_message = "The UI and its boundary must permit only the exact assessment route."
  }
  assert {
    condition     = aws_iam_user.ui.name == "clinical-trial-site-risk-monitor-dev-streamlit" && aws_iam_user.ui.permissions_boundary == aws_iam_policy.boundary.arn && !aws_iam_user.ui.force_destroy
    error_message = "Use the dedicated project identity and boundary without force deletion."
  }
}
