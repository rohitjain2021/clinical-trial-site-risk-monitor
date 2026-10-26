locals {
  # Separate routes keep Lambda invoke grants limited to intended methods and paths.
  api_routes = {
    health     = { method = "GET", path = "/health" }
    assessment = { method = "POST", path = "/site-assessments" }
  }
}

resource "aws_apigatewayv2_api" "this" {
  name          = "${var.function_name}-api"
  description   = "Authenticated health and operational site-risk assessment API"
  protocol_type = "HTTP"
  tags          = var.tags
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.this.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
  timeout_milliseconds   = 20000
}

# IAM authorization requires SigV4 signing and execute-api:Invoke permission.
resource "aws_apigatewayv2_route" "this" {
  for_each           = local.api_routes
  api_id             = aws_apigatewayv2_api.this.id
  route_key          = "${each.value.method} ${each.value.path}"
  authorization_type = "AWS_IAM"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/apigateway/${var.function_name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_apigatewayv2_stage" "dev" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "dev"
  auto_deploy = true
  tags        = var.tags

  default_route_settings {
    throttling_rate_limit  = 5
    throttling_burst_limit = 10
  }

  # Log request metadata only, never site records, request bodies, or credentials.
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api.arn
    format = jsonencode({
      requestId = "$context.requestId"
      routeKey  = "$context.routeKey"
      status    = "$context.status"
    })
  }
}

resource "aws_lambda_permission" "api" {
  for_each       = local.api_routes
  statement_id   = "AllowDevApi-${each.key}"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.this.function_name
  principal      = "apigateway.amazonaws.com"
  source_account = split(":", aws_lambda_function.this.arn)[4]
  source_arn     = "${aws_apigatewayv2_api.this.execution_arn}/dev/${each.value.method}${each.value.path}"
}
