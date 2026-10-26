data "archive_file" "lambda" {
  type        = "zip"
  output_path = "${path.module}/lambda.zip"

  source {
    content  = file(coalesce(var.source_file, "${path.module}/../../../services/lambda/handler.py"))
    filename = "handler.py"
  }
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_iam_role" "lambda" {
  name                 = "${var.function_name}-execution"
  permissions_boundary = var.permissions_boundary_arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
  tags = var.tags
}

# Terraform creates the log group, so the function does not need CreateLogGroup.
# Lambda chooses stream names at runtime; the wildcard covers only this group's streams.
resource "aws_iam_role_policy" "logging" {
  name = "write-function-logs"
  role = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.lambda.arn}:log-stream:*"
    }]
  })
}

resource "aws_lambda_function" "this" {
  function_name    = var.function_name
  description      = "Clinical Trial Site Risk Monitor validated risk assessment gateway"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.13"
  handler          = "handler.lambda_handler"
  architectures    = ["x86_64"]
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  memory_size      = 128
  timeout          = 8
  tags             = var.tags

  environment {
    variables = var.backend == null ? {} : { RISK_API_URL = var.backend.url }
  }

  # An empty VPC configuration supports explicit disconnect before ALB teardown.
  vpc_config {
    subnet_ids         = var.backend == null ? [] : var.backend.subnet_ids
    security_group_ids = var.backend == null ? [] : [var.backend.security_group_id]
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.lambda.name
  }

  depends_on = [aws_iam_role_policy.logging, aws_iam_role_policy.vpc]
}
