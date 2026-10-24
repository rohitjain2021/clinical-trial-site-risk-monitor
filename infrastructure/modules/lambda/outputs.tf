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
