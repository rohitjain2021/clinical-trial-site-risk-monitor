mock_provider "aws" {
  mock_data "aws_iam_policy" {
    defaults = { policy = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"ec2:DescribeInstances\"],\"Resource\":\"*\"}]}" }
  }
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = {
      arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    }
  }
  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/clinical-trial-site-risk-monitor-dev-lambda-boundary"
    }
  }
}

variables {
  ecr_repository_name  = "clinical-trial-site-risk-monitor-dev-risk-service"
  api_gateway_id       = "testapi"
  aws_account_id       = "123456789012"
  state_bucket         = "clinical-trial-site-risk-monitor-tfstate-dev-123456789012"
  github_repository    = "example-owner/example-repository"
  github_owner_id      = "123456"
  github_repository_id = "789012"
}

run "scoped_github_access" {
  command = apply

  assert {
    condition     = one([for s in jsondecode(aws_iam_role_policy.demo.policy).Statement : s if s.Sid == "CreateTaggedDemoCluster"]).Action == "eks:CreateCluster" && one([for s in jsondecode(aws_iam_role_policy.demo.policy).Statement : s if s.Sid == "CreateTaggedDemoCluster"]).Condition.StringEquals["aws:RequestTag/Name"] == local.demo_cluster_name && one([for s in jsondecode(aws_iam_role_policy.demo.policy).Statement : s if s.Sid == "CreateTaggedDemoCluster"]).Condition.StringEquals["aws:RequestedRegion"] == local.region
    error_message = "Cluster creation's required wildcard must be restricted to the exact demo tags and region."
  }

  assert {
    condition     = length(aws_iam_role_policy.demo.policy) < 10240 && jsondecode(aws_iam_role.demo.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == jsondecode(aws_iam_role.deployment.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"]
    error_message = "The demo role must fit IAM limits and retain exact main-only OIDC trust."
  }
  assert {
    condition     = toset(one([for s in jsondecode(aws_iam_role_policy.demo.policy).Statement : s if s.Sid == "DemoState"]).Resource) == toset(["${local.state_bucket_arn}/dev/eks/terraform.tfstate", "${local.state_bucket_arn}/dev/demo-app/terraform.tfstate"]) && alltrue([for key, role in local.demo_role_arns : one([for s in jsondecode(aws_iam_role_policy.demo.policy).Statement : s if s.Sid == "CreateBounded${title(key)}Role"]).Condition.StringEquals["iam:PermissionsBoundary"] == local.demo_boundaries[key]])
    error_message = "Demo state access and role creation must be restricted to the two bounded demo units."
  }

  assert {
    condition     = length(jsondecode(aws_iam_role_policy.image_publish.policy).Statement) == 2 && jsondecode(aws_iam_role_policy.image_publish.policy).Statement[0].Action == "ecr:GetAuthorizationToken" && jsondecode(aws_iam_role_policy.image_publish.policy).Statement[0].Resource == "*" && jsondecode(aws_iam_role_policy.image_publish.policy).Statement[0].Condition.StringEquals["aws:RequestedRegion"] == "us-east-1"
    error_message = "Only regional ECR login may use a wildcard resource in the publishing policy."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.image_publish.policy).Statement[1].Resource == "arn:aws:ecr:us-east-1:123456789012:repository/clinical-trial-site-risk-monitor-dev-risk-service" && toset(jsondecode(aws_iam_role_policy.image_publish.policy).Statement[1].Action) == toset(["ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage", "ecr:DescribeImages"])
    error_message = "Publishing must target only this repository, without image deletion or repository administration."
  }

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

  assert {
    condition     = toset(jsondecode(aws_iam_role_policy.api[0].policy).Statement[0].Resource) == toset(["arn:aws:apigateway:us-east-1::/apis/testapi", "arn:aws:apigateway:us-east-1::/apis/testapi/*", "arn:aws:apigateway:us-east-1::/tags/arn:aws:apigateway:us-east-1::/apis/testapi", "arn:aws:apigateway:us-east-1::/tags/arn:aws:apigateway:us-east-1::/apis/testapi/*"])
    error_message = "CI must manage only the exact existing API, without API collection access."
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_log_resource_policy.api.policy_document).Statement[0].Resource == "${local.api_log_group_arn}:log-stream:*" && jsondecode(aws_cloudwatch_log_resource_policy.api.policy_document).Statement[0].Condition.StringEquals["aws:SourceAccount"] == local.account_id
    error_message = "Log delivery must restrict the destination and source account."
  }
}
