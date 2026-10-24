mock_provider "aws" {
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::697078878651:oidc-provider/token.actions.githubusercontent.com"
    }
  }
  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::697078878651:policy/clinical-trial-site-risk-monitor-dev-lambda-boundary"
    }
  }
}

run "scoped_github_access" {
  command = apply

  assert {
    condition     = jsondecode(aws_iam_role.deployment.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com" && toset(jsondecode(aws_iam_role.deployment.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"]) == toset(local.trusted_subjects) && alltrue([for subject in local.trusted_subjects : endswith(subject, ":ref:refs/heads/main") && !strcontains(subject, "*")])
    error_message = "Trust must restrict the audience and exact main-branch repository subjects."
  }

  assert {
    condition     = alltrue([for statement in jsondecode(aws_iam_role_policy.deployment.policy).Statement : statement.Resource != "*" || try(statement.Sid == "DiscoverLogGroupsInDevRegion" && statement.Action == "logs:DescribeLogGroups" && statement.Condition.StringEquals["aws:RequestedRegion"] == "us-east-1", false)])
    error_message = "Only regional log-group discovery can use an unscoped resource."
  }

  assert {
    condition     = toset(jsondecode(aws_iam_policy.lambda_boundary.policy).Statement[0].Action) == toset(["logs:CreateLogStream", "logs:PutLogEvents"]) && jsondecode(aws_iam_policy.lambda_boundary.policy).Statement[0].Resource == "${local.log_group_arn}:log-stream:*"
    error_message = "The execution role boundary must cap permissions at this function's logs."
  }

  assert {
    condition     = one([for statement in jsondecode(aws_iam_role_policy.deployment.policy).Statement : statement if statement.Sid == "CreateBoundedExecutionRole"]).Condition.StringEquals["iam:PermissionsBoundary"] == aws_iam_policy.lambda_boundary.arn && one([for statement in jsondecode(aws_iam_role_policy.deployment.policy).Statement : statement if statement.Sid == "PassOnlyLambdaExecutionRole"]).Condition.StringEquals["iam:PassedToService"] == "lambda.amazonaws.com"
    error_message = "Role creation requires the fixed boundary and passing is restricted to Lambda."
  }

  assert {
    condition     = !anytrue([for statement in jsondecode(aws_iam_role_policy.deployment.policy).Statement : can(contains(tolist(statement.Action), "iam:DeleteRolePermissionsBoundary")) ? contains(tolist(statement.Action), "iam:DeleteRolePermissionsBoundary") : statement.Action == "iam:DeleteRolePermissionsBoundary"])
    error_message = "CI must not be allowed to remove the execution role's boundary."
  }
}
