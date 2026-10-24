output "function_name" {
  description = "Deployed Lambda function name."
  value       = aws_lambda_function.this.function_name
}

output "function_arn" {
  description = "Deployed Lambda function ARN."
  value       = aws_lambda_function.this.arn
}

output "execution_role_arn" {
  description = "Lambda execution role ARN."
  value       = aws_iam_role.lambda.arn
}

output "log_group_name" {
  description = "CloudWatch log group receiving Lambda platform and application logs."
  value       = aws_cloudwatch_log_group.lambda.name
}

output "api_gateway_id" {
  description = "HTTP API ID used to scope the CI deployment role's API management access."
  value       = aws_apigatewayv2_api.this.id
}

output "api_base_url" {
  description = "Dev HTTP API URL; both routes require AWS IAM SigV4 authentication."
  value       = aws_apigatewayv2_stage.dev.invoke_url
}

output "api_execution_arn" {
  description = "Execution ARN for granting route-scoped execute-api:Invoke permissions."
  value       = aws_apigatewayv2_api.this.execution_arn
}
