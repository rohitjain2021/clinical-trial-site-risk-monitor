locals {
  vpc_actions = [
    "ec2:CreateNetworkInterface", "ec2:DescribeNetworkInterfaces", "ec2:DescribeSubnets",
    "ec2:DeleteNetworkInterface", "ec2:AssignPrivateIpAddresses", "ec2:UnassignPrivateIpAddresses"
  ]
}

# AWS requires these resource-wildcard actions to manage Lambda Hyperplane ENIs.
# Keep them after disconnect so the service can finish asynchronous ENI cleanup.
resource "aws_iam_role_policy" "vpc" {
  name = "manage-lambda-vpc-interfaces"
  role = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "LambdaServiceNetworking", Effect = "Allow", Action = local.vpc_actions, Resource = "*"
        Condition = { StringEquals = { "aws:RequestedRegion" = "us-east-1" } }
      },
      {
        Sid       = "DenyFunctionCodeNetworking", Effect = "Deny", Action = concat(local.vpc_actions, ["ec2:DetachNetworkInterface"]), Resource = "*"
        Condition = { ArnEquals = { "lambda:SourceFunctionArn" = "arn:aws:lambda:us-east-1:${split(":", aws_iam_role.lambda.arn)[4]}:function:${var.function_name}" } }
      }
    ]
  })
}
