# Clinical Trial Site Risk Monitor

Clinical trial site risk monitoring platform using AWS, Kubernetes, Snowflake, Terraform, Terragrunt, and AI-driven risk analysis.

## Problem Statement

Clinical trials are often conducted across multiple hospitals, clinics, and research sites. Each site is expected to meet operational targets such as patient enrollment goals, study timelines, protocol compliance, and timely issue resolution.

Some sites may begin falling behind without the problem being immediately obvious. Slow enrollment, repeated delays, patient dropouts, protocol deviations, or unresolved operational issues can eventually affect the overall clinical trial timeline and increase cost.

### Example

Suppose a clinical trial site is expected to enroll **60 patients**, but it has enrolled only **21 patients**. The site is also **18 days behind schedule** and has **3 unresolved operational issues**.

This site may represent a higher operational risk and should receive attention before the problems become more serious.

## What We Are Trying to Solve

The goal of this project is to provide a simple **Clinical Trial Site Risk Monitor** that helps clinical operations teams quickly identify:

- which trial sites are performing normally
- which sites are beginning to fall behind
- which sites may represent a high risk
- the main reasons a site has been classified as risky

The application provides an easy way to review trial-site performance and detect potential problems earlier, helping teams focus attention on the sites that need it most.

## Architecture

![Clinical Trial Site Risk Monitor architecture showing signed Streamlit API integration, deployed Lambda, internal ALB, EKS/FastAPI, ECR image delivery, and planned Snowflake and Bedrock connections](docs/images/clinical-trial-site-risk-monitor-architecture.png)

Terragrunt manages environment configuration and orchestrates Terraform, which provisions the AWS infrastructure shown above.

The diagram shows the target architecture. EKS/FastAPI and the internal ALB now run privately using the published ECR image. Lambda calls the private ALB. Streamlit supports signed API requests; its hosted connection requires the private Secrets setup described in the [Streamlit guide](docs/streamlit.md). Snowflake and Bedrock remain planned.

## Development Setup

See the [development setup guide](docs/setup.md) for installation and verification instructions, starting with Terraform on Windows.

## CI/CD

GitHub Actions runs checks on pull requests and produces a development deployment plan on `main`. An explicit manual workflow run deploys the Lambda through Terragrunt and Terraform, using OIDC authentication and S3 state locking. See the [CI/CD guide](docs/cicd.md) for workflow behavior and AWS permissions.

The manual [EKS deployment workflow](docs/deployment.md) plans by default and provisions EKS/FastAPI when deployment is explicitly selected. Resources remain running; there is no Start/Stop lifecycle or automatic destruction. The main-branch EKS/FastAPI workflow has passed. The separate operator-run ALB unit has also passed private HTTP verification; see the [ALB guide](docs/alb.md).

**Development EKS status:** provisioned, with FastAPI running privately. Health, risk assessment, cache-control, and invalid-input checks passed through both the Kubernetes Service and private ALB. Resources remain running until teardown is explicitly requested.

## API

The development HTTP API provides authenticated `GET /health` and `POST /site-assessments` routes. Lambda validates site records and calls FastAPI through the private ALB to return prototype risk levels and reasons. Records are not stored. See the [API guide](docs/api.md) for the contract, authentication, and example data.

## Things to Do

The authenticated API Gateway -> Lambda -> ALB -> FastAPI path is deployed and verified. The following work remains:

- [x] Document [prototype risk rules](docs/risk-rules.md), classification reasons, and sample cases. Thresholds require review before operational use.
- [x] Implement and test the standalone prototype risk calculation locally; it is used by FastAPI behind the deployed API.
- [x] Build and test the [FastAPI risk service locally](docs/risk-service.md) using representative site data. It is deployed privately on EKS and connected to Lambda through the ALB.
- [x] Build and test the [FastAPI container locally](docs/container.md).
- [x] Add container build and HTTP checks to GitHub Actions; each run reports its result.
- [x] Provision the private [ECR risk-service repository](docs/ecr.md) through Terraform and Terragrunt.
- [x] Configure scoped image publishing to ECR through GitHub Actions (manual run on `main`).
- [x] Run the publishing workflow after merge and verify the first commit-tagged image in ECR.
- [x] Prepare and validate the [EKS Terraform plan and running costs](docs/eks.md), reusing the existing default VPC and subnets.
- [x] Implement a basic manual EKS/FastAPI plan-and-deploy workflow.
- [x] Configure encrypted operator settings in GitHub Actions.
- [x] Verify EKS worker provisioning through Terraform.
- [x] Merge the IAM fixes and verify FastAPI in the live cluster.
- [x] Merge the verification-job routing fix and pass the GitHub deployment workflow.
- [x] Review the EKS plan and provision through Terraform and Terragrunt.
- [x] Provision and verify the private Application Load Balancer through Terraform/Terragrunt.
- [x] Connect Lambda to the risk service through the ALB and verify signed High/Medium/Low assessments.
- [x] Merge the Lambda integration changes; the backend is deployed and verified.
- [ ] Add Snowflake storage for trial-site data and assessment results.
- [x] Build and verify a simple local Streamlit interface with copy-paste JSON and risk results.
- [x] Add signed API requests and safe backend errors to the single-site Streamlit UI.
- [x] Save private Community Cloud Secrets and verify the hosted Streamlit form (High risk and five reasons).
- [ ] Extend Streamlit for multiple sites.
- [x] Define dedicated, route-scoped Streamlit API access through Terraform and Terragrunt. Hosting uses Streamlit Community Cloud.
- [x] Implement optional Nova Micro explanations, scoped pod access, and UI success/fallback behavior; test the real model locally.
- [ ] Publish and deploy the Bedrock-capable image, then verify EKS identity and the hosted AI explanation.
- [ ] Extend CI/CD to deploy the ALB unit and remaining application components.
- [ ] Add monitoring, alerts, and end-to-end tests for the complete workflow.
- [x] Update the architecture diagram with GitHub Actions, Docker, ECR, service connections, and implemented versus planned components.

## Documentation

### Bedrock Explanations

[Read the Bedrock guide](docs/bedrock.md) for the Nova Micro model, prompt, response contract, scoped IAM role, fallback behavior, and rollout steps.

### Streamlit UI and API Connection

[Read the Streamlit guide](docs/streamlit.md) for hosted Secrets configuration, scoped AWS access, copy-paste sample data, and local setup.

### EKS Deployment

[Read the deployment guide](docs/deployment.md) for the manual plan/apply workflow, current scope, and failure recovery.

### Lambda Backend Connection

[Read the Lambda connection guide](docs/lambda-backend.md) for private settings, VPC permissions, backend errors, and disconnect-before-teardown steps.

### Private Application Load Balancer

[Read the ALB guide](docs/alb.md) for worker routing, security groups, operator deployment, verification, and teardown order.

### EKS Planning

[Read the EKS guide](docs/eks.md) for the existing network, proposed cluster, operator access, cost estimate, and cleanup boundaries.

### Container Registry

[Read the ECR guide](docs/ecr.md) for the repository name, security settings, Terraform/Terragrunt commands, and deployment status.

### Local Container

[Read the container guide](docs/container.md) for Docker prerequisites, image build commands, local requests, and cleanup.

### Local Risk Service

[Read the FastAPI service guide](docs/risk-service.md) to install, run, and test the local risk assessment endpoints.

### Risk Rules

[Read the prototype risk rules](docs/risk-rules.md) for proposed Low, Medium, and High thresholds, calculation examples, and limitations. These prototype rules are implemented in FastAPI and available through the authenticated deployed API.

### Repository Security

[Read the security guide](docs/security.md) for private deployment configuration, credential protection, CI secret scanning, and Git history limitations.

### Tools and Technologies

[Read the technology guide](docs/technologies.md) for what each tool does, why we use it, and how it fits this project, with examples and implemented versus planned status.

### Development Setup

[Read the setup guide](docs/setup.md) for tool installation, local testing, and Terraform/Terragrunt configuration.

### API Guide

[Read the API guide](docs/api.md) for endpoints, authentication, submission fields, and request examples.

### CI/CD and Deployment

[Read the CI/CD guide](docs/cicd.md) for GitHub Actions workflows, AWS access, deployment approval, and verification.
