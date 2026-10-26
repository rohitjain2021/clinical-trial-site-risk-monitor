# Clinical Trial Site Risk Monitor

A prototype for monitoring clinical trial site performance using rule-based risk scoring and AI-generated explanations.

## Problem Statement

One clinical trial can run across several hospitals, clinics, and research sites. Each site has patient enrollment targets, study deadlines, and operational issues to resolve.

Some sites meet their targets while others fall behind. The challenge is to identify **which site needs attention and why**, before delays affect the wider trial.

### Example: Which Site Needs Attention?

The following fictional sites illustrate three different situations:

| Trial site | Patients enrolled / target | Days behind schedule | Unresolved issues | Prototype risk | What the numbers show |
|---|---|---:|---:|---|---|
| Northbridge Research Center | 21 / 60 — **35%** | 18 | 3 | **High** | Enrollment is low, the site is well behind schedule, and several issues remain open. |
| Harborview Study Center | 45 / 60 — **75%** | 9 | 1 | **Medium** | Enrollment is below the prototype target threshold, with a delay and an open issue. |
| Lakeside Research Clinic | 54 / 60 — **90%** | 0 | 0 | **Low** | The displayed metrics are within the prototype thresholds, with no schedule delay or open issues. |

The application also checks patient dropouts and protocol deviations. For these examples, neither raises the overall rating above the level shown. The current app assesses **one site at a time**; this table compares the examples to make the problem easier to understand.

These ratings follow the project's [prototype risk rules](docs/risk-rules.md). They describe operational concerns, not patient safety or treatment risk. Low means no monitored metric crossed those thresholds; it does not mean there is no risk.

## What We Are Trying to Solve

The goal is to make a site's operational status easy to review without manually interpreting every number.

| Question | How the application helps |
|---|---|
| Is this site falling behind? | Shows enrollment progress, schedule delay, and unresolved issues. |
| How much attention does it need? | Applies consistent Python rules to classify the site as Low, Medium, or High. |
| Why was it given that rating? | Lists the measured factors and thresholds that contributed to the result. |
| What does the result mean in plain language? | Uses Amazon Bedrock Nova Micro to explain the calculated result without changing the rating. |

**Using the app:** paste a readable site report or fill in the fields, select **Assess site**, then review the rating, reasons, and optional AI explanation. No JSON editing is required.

## Architecture

![Clinical Trial Site Risk Monitor architecture showing the verified Streamlit, API Gateway, Lambda, internal ALB, EKS/FastAPI, and Nova Micro connection, with ECR image delivery, planned Snowflake storage, and planned SNS email notifications](docs/images/clinical-trial-site-risk-monitor-architecture.png)

Terragrunt manages environment configuration and orchestrates Terraform, which provisions the AWS infrastructure shown above.

The working request path is Streamlit Community Cloud -> API Gateway -> Lambda -> internal ALB -> FastAPI on EKS. FastAPI calculates the risk using Python rules and calls Amazon Bedrock Nova Micro for a separate explanation. The hosted UI and AI response are verified. GitHub Actions publishes the container to ECR; Terraform and Terragrunt manage AWS infrastructure. Snowflake storage remains planned. The SNS notification branch has been implemented and tested locally, including a confirmed demo email. Its hosted application rollout remains pending; the diagram marks that branch as planned until the updated image is deployed.

## Development Setup

See the [development setup guide](docs/setup.md) for installation and verification instructions, starting with Terraform on Windows.

## CI/CD

GitHub Actions runs checks on pull requests and produces a development deployment plan on `main`. An explicit manual workflow run deploys the Lambda through Terragrunt and Terraform, using OIDC authentication and S3 state locking. See the [CI/CD guide](docs/cicd.md) for workflow behavior and AWS permissions.

The manual [EKS deployment workflow](docs/deployment.md) plans by default and provisions EKS/FastAPI when deployment is explicitly selected. Resources remain running; there is no Start/Stop lifecycle or automatic destruction. The main-branch EKS/FastAPI workflow has passed. The separate operator-run ALB unit has also passed private HTTP verification; see the [ALB guide](docs/alb.md).

**Development status:** FastAPI and Nova Micro explanations are deployed. Signed API tests returned the expected High, Medium, and Low results with available AI explanations. The hosted Streamlit page also displays the AI response. Health, cache-control, and invalid-input checks passed. Resources remain running until teardown is explicitly requested.

## API

The development HTTP API provides authenticated `GET /health` and `POST /site-assessments` routes. Lambda validates site records and calls FastAPI through the private ALB to return prototype risk levels, reasons, and an optional Nova Micro explanation. AI text does not determine or change the score; if the model is unavailable, the calculated risk result still returns. Records are not stored. See the [API guide](docs/api.md) for the contract, authentication, and example data.

## Documentation

### Assessment Email Notifications

[Read the SNS notification guide](docs/notifications.md) for the small assessment-event demo, private recipient settings, subscription confirmation, scoped permissions, and rollout steps.

### Bedrock Explanations

[Read the Bedrock guide](docs/bedrock.md) for the Nova Micro model, prompt, response contract, scoped IAM role, fallback behavior, and rollout steps.

### Streamlit UI and API Connection

[Read the Streamlit guide](docs/streamlit.md) for the dashboard design, copy-paste site reports, manual input, private hosted configuration, and local setup.

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
