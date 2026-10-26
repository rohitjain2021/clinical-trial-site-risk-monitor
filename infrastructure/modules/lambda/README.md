# Lambda Risk Gateway

Packages the standard-library Python handler and defines Lambda, its execution role, finite CloudWatch logs, and the IAM-authenticated HTTP API. Lambda validates one site record and forwards it to FastAPI through the private ALB. See the [API guide](../../../docs/api.md) and [backend connection guide](../../../docs/lambda-backend.md).

## Configuration

The handler remains `handler.lambda_handler`, Python 3.13, 128 MB. Backend HTTP timeout is 12 seconds, Lambda timeout 18 seconds, and API integration timeout 20 seconds, allowing the optional Nova Micro explanation. Only `handler.py` is packaged; no third-party dependencies or local caches are included. `source_code_hash` tracks code changes.

The optional sensitive `backend` object contains the internal project ALB URL, two existing subnet IDs, and the dedicated client security group ID. The Terragrunt unit reads this from ignored `backend.local.hcl`, generated from private ALB state. A null backend removes the URL and VPC attachment; liveness stays available and valid assessments return 503. No networking or backend resources are created by this module.

## Permissions

The role trusts only Lambda. Log writes stay scoped to this function's streams. AWS requires six regional EC2 actions on wildcard resources to manage VPC interfaces; the inline policy and separate operator-managed boundary explicitly deny these actions to function code using `lambda:SourceFunctionArn`. Keep the role and permissions until AWS releases interfaces after disconnect. No Bedrock, Snowflake, or data-storage permissions are granted.

Both API routes retain AWS_IAM authentication, route-specific invocation grants, throttling, and metadata-only finite access logs. The ALB client security group limits outbound traffic to private HTTP; attaching to the existing public subnets does not grant internet access.

## Validation and Cleanup

Mocked Terraform tests cover logging, trust, authorization, VPC connect/disconnect, timeout ordering, rejected backend settings, and function-code ENI isolation. Handler tests cover risk forwarding and sanitization without AWS. Live signed API tests reached FastAPI and returned High, Medium, and Low results; invalid requests returned 400 and unsigned requests 403.

Before ALB/EKS teardown, explicitly disconnect this Lambda through a reviewed saved Terraform plan. Wait for AWS to release the client-group interfaces, then destroy ALB, application, and EKS in order. Lambda/API and IAM bootstrap remain unless separately requested for removal. No idle timer or automatic teardown is configured.
