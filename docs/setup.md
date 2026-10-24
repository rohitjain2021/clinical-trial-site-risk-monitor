# Development Setup

This guide covers local setup on Windows using PowerShell. We will add instructions for each tool as it is introduced into the project.

## 1. Install Terraform

Terraform provisions the AWS infrastructure for this project. It is a standalone command-line tool, installed separately from Python packages in `requirements.txt`.

### Prerequisite

Check that Windows Package Manager (WinGet) is available:

```powershell
winget --version
```

If WinGet is unavailable, install or update [App Installer from Microsoft](https://learn.microsoft.com/windows/package-manager/winget/).

### Installation

Install Terraform version `1.16.6` for your Windows user account:

```powershell
winget install --id Hashicorp.Terraform --exact --version 1.16.6 --source winget --scope user --accept-source-agreements --accept-package-agreements
```

WinGet downloads the Terraform binary from HashiCorp's release service and verifies the installer hash. See the [official Terraform installation page](https://developer.hashicorp.com/terraform/install) for manual installation options.

### Verification

Open a new PowerShell terminal after installation so it picks up the updated `PATH`, then run:

```powershell
terraform -version
```

The output should include `Terraform v1.16.6`. If the command is unavailable in VS Code, restart VS Code and open a new terminal.

Installing Terraform does not create AWS resources. AWS credentials are needed later when we configure the AWS provider and deploy infrastructure.

## 2. Install Terragrunt

Terragrunt manages environment configuration and orchestrates Terraform. Install it separately from Terraform and Python packages. See the [official Terragrunt installation guide](https://docs.terragrunt.com/getting-started/install/) for other installation options.

### Prerequisites

Use the same Windows Package Manager (WinGet) installed above, and confirm Terraform is available:

```powershell
winget --version
terraform -version
```

### Installation

Install Terragrunt version `1.1.6` for your Windows user account:

```powershell
winget install --id Gruntwork.Terragrunt --exact --version 1.1.6 --source winget --scope user --accept-source-agreements --accept-package-agreements --disable-interactivity
```

WinGet downloads the executable from Gruntwork's GitHub releases, verifies its hash, and adds a command alias to your user `PATH`.

### Verification and Smoke Test

Open a new PowerShell terminal, then run:

```powershell
terragrunt --version
terragrunt --help
```

Expected results:

- `terragrunt --version` prints `terragrunt version v1.1.6`.
- `terragrunt --help` displays CLI usage and available commands.
- Both commands exit successfully (exit code `0`). Check `$LASTEXITCODE` immediately after each command if needed.

These checks passed on the development machine after installation. They verify that the executable runs; infrastructure configuration and AWS integration will be tested when those are added.

If PowerShell cannot find `terragrunt`, restart VS Code and open a new terminal. You can also check command resolution with:

```powershell
Get-Command terraform, terragrunt | Select-Object Name, Source
```

The verification commands above do not create AWS resources or require AWS credentials.

## 3. Run the Basic Lambda Locally

The initial function is in `services/lambda/handler.py`. It uses only Python's standard library and requires no additional packages. The AWS Lambda handler setting will be `handler.lambda_handler`, with `handler.py` at the root of the deployment ZIP.

With Python 3 installed, run this smoke test from the repository root in PowerShell:

```powershell
Push-Location services/lambda
try {
    python -c "import json; from handler import lambda_handler; response = lambda_handler({}, None); assert response['statusCode'] == 200; assert response['headers']['Content-Type'] == 'application/json'; assert json.loads(response['body'])['status'] == 'ok'; print(json.dumps(response, indent=2))"
    if ($LASTEXITCODE -ne 0) { throw 'Lambda smoke test failed.' }
} finally {
    Pop-Location
}
```

Expected response:

```json
{
  "statusCode": 200,
  "headers": {
    "Content-Type": "application/json",
    "Cache-Control": "no-store"
  },
  "body": "{\"status\": \"ok\", \"service\": \"clinical-trial-site-risk-monitor\"}"
}
```

The body is a JSON string to match the API Gateway proxy response format. This local check does not deploy resources. The HTTP API now exposes authenticated health and validation-only POST routes; see the [API guide](api.md). Risk analysis is not implemented yet.

## 4. Validate the Lambda Terraform Module

The [Lambda module](../infrastructure/modules/lambda/README.md) packages the Python handler, creates a dedicated IAM execution role with log-stream-only permissions, and configures a CloudWatch log group with finite retention.

From the repository root, run each command and confirm it exits successfully before continuing:

```powershell
terraform fmt -check -recursive infrastructure
terraform -chdir=infrastructure/modules/lambda init -backend=false
terraform -chdir=infrastructure/modules/lambda validate
terraform -chdir=infrastructure/modules/lambda test
```

Expected results: formatting passes, initialization installs the AWS and archive providers, validation reports success, and both Terraform tests pass. Tests mock AWS and do not require credentials or create AWS resources. Initialization needs internet access to download providers.

## 5. Plan the Development Environment with Terragrunt

The configuration is organized as follows:

```text
infrastructure/
  bootstrap/
    state-backend/            # Terraform-managed S3 state bucket
  live/
    root.hcl                  # Shared AWS provider, tags, and S3 backend
    dev/
      env.hcl                 # Development account and region
      lambda/
        terragrunt.hcl        # Lambda module source and inputs
  modules/
    lambda/                   # Terraform resources and security tests
  state/                      # Bootstrap local state and backups; ignored by Git
```

The development configuration targets AWS account `697078878651` in `us-east-1`. The generated provider uses `allowed_account_ids` to reject credentials for another account. Credentials come from your AWS configuration or environment, never from committed files. If using a named profile, set `$env:AWS_PROFILE` to that profile before running these commands.

Terragrunt explicitly runs Terraform and passes the absolute Python source path so packaging works from its disposable cache. The planned function name is `clinical-trial-site-risk-monitor-dev`, with 14-day log retention and project, environment, and management tags.

### State Storage

Application state uses S3 bucket `clinical-trial-site-risk-monitor-tfstate-dev-697078878651` in `us-east-1`. Lambda's state key is `dev/lambda/terraform.tfstate`. Terraform native S3 locking uses the corresponding `.tflock` object; this requires Terraform 1.10 or later and does not need DynamoDB.

The [backend bootstrap guide](../infrastructure/bootstrap/state-backend/README.md) explains how Terraform provisions encryption, versioning, disabled ACLs, public-access blocking, HTTPS-only access, and deletion protection. Run its bootstrap steps before initializing an application unit in a new account. This bucket is for infrastructure state, not patient or trial-site data.

The bootstrap stack keeps its own state locally in `infrastructure/state/bootstrap/terraform.tfstate`; back that file up securely. Application deployments and the future CI pipeline use S3 state. State, saved plans, and cache directories are ignored by Git.

For an existing locally initialized Lambda unit, preserve its state and cache and run `terragrunt --working-dir infrastructure/live/dev/lambda init -migrate-state` once. Review any state-copy prompt; do not discard local state or use `-reconfigure` instead of migrating existing resources. A fresh checkout uses normal `init` against the existing bucket.

### Validation and Plan

From the repository root, run each command and check that it succeeds before continuing:

```powershell
terragrunt --working-dir infrastructure/live/dev/lambda hcl validate
terragrunt --working-dir infrastructure/live/dev/lambda init -input=false
terragrunt --working-dir infrastructure/live/dev/lambda validate
terragrunt --working-dir infrastructure/live/dev/lambda plan -input=false "-out=dev-lambda.tfplan"
```

Initialization downloads providers and configures the S3 backend. Planning uses your AWS credentials to check the target account and access remote state, acquires a state lock, packages the handler locally, and previews changes. It does not deploy application resources or verify that your identity has every permission required to deploy them.

The Lambda unit now manages 12 resources including API Gateway, its two IAM-authenticated routes, access logs, and route-specific invoke grants. An unchanged deployed environment should report no changes. Review the account, region, function name, IAM policy scope, and log retention in every plan. The saved plan and ZIP are in the unit's ignored `.terragrunt-cache`; retain the cache while reviewing that plan. Provider lock files are committed for repeatable provider selection. See the [API bootstrap order](api.md) before provisioning a new environment.

## 6. GitHub Actions Access and Workflow

The [CI/CD guide](cicd.md) documents the Terraform-managed OIDC provider, scoped deployment role, Lambda permissions boundary, and GitHub Actions workflow. The access stack is in `infrastructure/live/dev/github-actions` and uses its own S3 state key.

Pull requests run checks without AWS credentials. Main-branch runs authenticate through OIDC and plan the development Lambda. Deployment requires a manual main-branch workflow run with the `deploy` option checked; this is not a separate environment reviewer gate.

The deployment role cannot bootstrap or modify its own permissions. An operator manages the GitHub access stack through Terraform/Terragrunt. The Lambda unit passes the pre-provisioned execution-role boundary ARN to satisfy the deployment policy's role-creation restriction.

## Next Steps

Push and merge the implementation to `main`, verify the first GitHub Actions plan run, then explicitly trigger a development deployment after reviewing the plan. All AWS resource creation and configuration changes remain in Terraform/Terragrunt.
