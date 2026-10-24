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

## Next Steps

Configure AWS CLI access, choose the AWS account and region, then create the Lambda Terraform module and Terragrunt development configuration.
