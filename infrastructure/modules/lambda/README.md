# Lambda Module

Packages the Python handler and defines Lambda, its execution role and logging policy, CloudWatch log groups, and an IAM-authenticated HTTP API. See the [API guide](../../../docs/api.md) for routes and the validation-only POST contract.

## Resources and Permissions

- Python `3.13`, handler `handler.lambda_handler`, 128 MB memory, and a 3-second timeout.
- Only `handler.py` is packaged at the ZIP root. Python caches and other local files are excluded by construction. This handler has no third-party dependencies.
- Code changes update `source_code_hash`, so Terraform detects new deployment packages.
- The execution role trusts only the `lambda.amazonaws.com` service principal.
- Its only granted actions are `logs:CreateLogStream` and `logs:PutLogEvents`, restricted to `arn:...:log-group:/aws/lambda/<function-name>:log-stream:*`. The wildcard covers runtime-generated stream names inside that one group.
- Terraform creates the log group before the function, so the execution role does not receive `logs:CreateLogGroup` or log-deletion permissions.
- Logs have configurable finite retention (14 days by default).

API Gateway invocation grants are restricted to the source account, API ID, development stage, method, and path. Both routes require IAM authentication and have throttling and metadata-only access logs. No AWS managed policies, function URL, VPC permissions, or access to Bedrock, Snowflake, or storage services are configured. The execution role controls AWS API access; it does not restrict outbound internet traffic.

The identity running Terraform is separate from the execution role. It needs permissions to manage these resources and `iam:PassRole` restricted to this execution role, with `iam:PassedToService` set to `lambda.amazonaws.com`. This module does not grant deployment permissions to your user. The development Terragrunt unit also passes `permissions_boundary_arn`, provisioned by the GitHub access stack, to cap the execution role at logging permissions even if CI edits its inline policy.

## Usage

Call this module from an environment root that configures the AWS provider. For example, from `infrastructure/live/dev/lambda/`:

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "health_lambda" {
  source = "../../../modules/lambda"

  function_name      = "clinical-trial-site-risk-monitor-dev"
  log_retention_days = 14
  tags = {
    Project     = "clinical-trial-site-risk-monitor"
    Environment = "dev"
  }
}
```

This is a usage example; the environment root and Terragrunt configuration will be added separately. When using Terragrunt's source cache, explicitly pass `source_file` as an absolute path to the repository's `services/lambda/handler.py`. The module's relative default is intended for direct use within this repository.

Inputs: required `function_name`; optional `source_file`, `log_retention_days`, `permissions_boundary_arn`, and `tags`. Outputs: `function_name`, `function_arn`, `execution_role_arn`, `log_group_name`, `api_gateway_id`, `api_base_url`, and `api_execution_arn`.

## Local Validation

From the repository root:

```powershell
terraform fmt -check -recursive infrastructure
terraform -chdir=infrastructure/modules/lambda init -backend=false
terraform -chdir=infrastructure/modules/lambda validate
terraform -chdir=infrastructure/modules/lambda test
```

Tests use a mocked AWS provider to check the execution policy's allowed actions, resource scope, trust principal, logging configuration, and rejection of indefinite retention. The real archive provider packages the handler locally. These checks download provider plugins but do not call AWS or deploy resources. Keep `.terraform.lock.hcl` in version control; generated ZIPs, provider downloads, and state files are ignored.

Mock tests do not verify account permissions or actual log delivery. Review a plan from the environment configuration before applying, then invoke the deployed function and verify its response and CloudWatch logs.

References: [AWS log-stream resource scoping](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/iam-identity-based-access-control-cwl.html), [Lambda log groups](https://docs.aws.amazon.com/lambda/latest/dg/monitoring-cloudwatchlogs-loggroups.html), and [Terraform Lambda resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function).
