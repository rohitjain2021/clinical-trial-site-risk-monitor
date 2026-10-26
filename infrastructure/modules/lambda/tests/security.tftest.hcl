mock_provider "aws" {
  mock_resource "aws_lambda_function" {
    defaults = {
      arn        = "arn:aws:lambda:us-east-1:123456789012:function:test-health"
      invoke_arn = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:123456789012:function:test-health/invocations"
    }
  }
  mock_resource "aws_apigatewayv2_api" {
    defaults = {
      execution_arn = "arn:aws:execute-api:us-east-1:123456789012:testapi"
    }
  }
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
    condition     = jsondecode(aws_iam_role_policy.vpc.policy).Statement[1].Effect == "Deny" && jsondecode(aws_iam_role_policy.vpc.policy).Statement[1].Condition.ArnEquals["lambda:SourceFunctionArn"] == "arn:aws:lambda:us-east-1:123456789012:function:test-health" && jsondecode(aws_iam_role_policy.vpc.policy).Statement[0].Condition.StringEquals["aws:RequestedRegion"] == "us-east-1"
    error_message = "ENI permissions must be regional and explicitly denied to function code."
  }
  assert {
    condition     = length(aws_lambda_function.this.vpc_config[0].subnet_ids) == 0 && !contains(keys(aws_lambda_function.this.environment[0].variables), "RISK_API_URL")
    error_message = "A disconnected Lambda must have no backend URL or VPC subnet attachment."
  }
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

  assert {
    condition     = length(aws_apigatewayv2_route.this) == 2 && alltrue([for route in aws_apigatewayv2_route.this : route.authorization_type == "AWS_IAM"])
    error_message = "Exactly two authenticated routes must be exposed."
  }

  assert {
    condition     = aws_lambda_permission.api["health"].source_arn == "arn:aws:execute-api:us-east-1:123456789012:testapi/dev/GET/health" && aws_lambda_permission.api["assessment"].source_arn == "arn:aws:execute-api:us-east-1:123456789012:testapi/dev/POST/site-assessments" && alltrue([for permission in aws_lambda_permission.api : permission.principal == "apigateway.amazonaws.com" && permission.source_account == "123456789012"])
    error_message = "Invoke grants must restrict API ID, account, stage, method, and path."
  }

  assert {
    condition     = aws_apigatewayv2_stage.dev.default_route_settings[0].throttling_rate_limit == 5 && aws_apigatewayv2_stage.dev.default_route_settings[0].throttling_burst_limit == 10 && aws_cloudwatch_log_group.api.retention_in_days == 14
    error_message = "Use bounded request rates and finite API access log retention."
  }
}

run "connect_only_configured_backend" {
  command = apply
  variables {
    backend = {
      url               = "http://internal-clinical-trial-risk-dev-alb-example.us-east-1.elb.amazonaws.com"
      subnet_ids        = ["subnet-aaaaaaaaaaaaaaaaa", "subnet-bbbbbbbbbbbbbbbbb"]
      security_group_id = "sg-ccccccccccccccccc"
    }
  }
  assert {
    condition     = toset(aws_lambda_function.this.vpc_config[0].subnet_ids) == toset(var.backend.subnet_ids) && toset(aws_lambda_function.this.vpc_config[0].security_group_ids) == toset([var.backend.security_group_id]) && aws_lambda_function.this.environment[0].variables["RISK_API_URL"] == var.backend.url && aws_lambda_function.this.timeout == 18 && aws_apigatewayv2_integration.lambda.timeout_milliseconds == 20000
    error_message = "Use only the configured ALB client network, with backend timeout shorter than Lambda and API timeouts."
  }
}

run "reject_unrelated_backend" {
  command = plan
  variables {
    backend = {
      url               = "http://unrelated.example.com"
      subnet_ids        = ["subnet-aaaaaaaaaaaaaaaaa", "subnet-bbbbbbbbbbbbbbbbb"]
      security_group_id = "sg-ccccccccccccccccc"
    }
  }
  expect_failures = [var.backend]
}

run "reject_indefinite_retention" {
  command = plan
  variables {
    log_retention_days = 0
  }
  expect_failures = [var.log_retention_days]
}
