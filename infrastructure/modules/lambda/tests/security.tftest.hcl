mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/test-health-execution"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/lambda/test-health"
    }
  }
}

variables {
  function_name = "test-health"
}

run "least_privilege_logging" {
  command = apply

  assert {
    condition     = toset(jsondecode(aws_iam_role_policy.logging.policy).Statement[0].Action) == toset(["logs:CreateLogStream", "logs:PutLogEvents"])
    error_message = "The execution policy must grant only log-stream creation and log writes."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.logging.policy).Statement[0].Resource == "arn:aws:logs:us-east-1:123456789012:log-group:/aws/lambda/test-health:log-stream:*"
    error_message = "Log writes must be restricted to this function's log streams."
  }

  assert {
    condition     = jsondecode(aws_iam_role.lambda.assume_role_policy).Statement[0].Principal.Service == "lambda.amazonaws.com"
    error_message = "Only the Lambda service should be trusted to assume the execution role."
  }

  assert {
    condition     = aws_cloudwatch_log_group.lambda.retention_in_days == 14 && aws_lambda_function.this.logging_config[0].log_group == aws_cloudwatch_log_group.lambda.name
    error_message = "The function must use the managed log group with finite retention."
  }
}

run "reject_indefinite_retention" {
  command = plan
  variables {
    log_retention_days = 0
  }
  expect_failures = [var.log_retention_days]
}
