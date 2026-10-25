# Terraform

**Status: implemented.** Our workflow pins Terraform to `1.16.6`.

## What it is and what it does

Terraform is an infrastructure-as-code tool. We describe desired resources in `.tf` files, and Terraform compares that configuration with its tracked state and AWS before proposing changes.

## Why we use it

We want infrastructure changes to be reviewable, repeatable, and versioned alongside the application. Lambda, API Gateway, IAM permissions, logging, and the state bucket are defined in code instead of being configured manually in the AWS console.

## How we use it in this project

- `infrastructure/modules/lambda/` defines Lambda and its HTTP API.
- `infrastructure/modules/github-actions/` defines GitHub-to-AWS trust and deployment permissions.
- `infrastructure/bootstrap/state-backend/` defines the S3 state bucket and its protections.

Providers translate Terraform operations into service API calls. Our modules declare the HashiCorp AWS provider; the archive provider builds the Lambda ZIP. Lock files record selected provider versions.

## Small example

From our Lambda module:

```hcl
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}
```

This describes a log group and its retention. A `plan` previews changes; `apply` performs them. A successful plan does not prove that deployment permissions or application behavior are correct.

[Official Terraform introduction](https://developer.hashicorp.com/terraform/intro).

# Terragrunt

**Status: implemented.** Our workflow pins Terragrunt to `1.1.6`.

## What it is and what it does

Terragrunt orchestrates Terraform configurations. It supplies inputs, shares configuration between units, and manages dependencies between them. Terraform still performs resource provisioning.

## Why we use it

We want reusable modules with separate environment settings instead of copied Terraform resource definitions for every environment.

## How we use it in this project

`infrastructure/live/root.hcl` generates shared AWS provider and S3 backend configuration. `dev/env.hcl` supplies the region, account, and bucket. Each unit's `terragrunt.hcl` selects a module and passes inputs. The GitHub access unit reads the API ID from the Lambda unit's outputs to scope deployment permissions.

Only `dev` is configured today. `staging` and `prod` are possible future environments, not existing deployments. Terragrunt's `.terragrunt-cache` is disposable; our application state lives in S3.

## Small example

Run from the repository root:

```powershell
terragrunt --working-dir infrastructure/live/dev/lambda plan
```

Terragrunt loads development settings and runs Terraform against the Lambda/API unit. The `dev` directory is an environment configuration, not a Git branch requirement.

[Official Terragrunt overview](https://docs.terragrunt.com/getting-started/overview/).

# Python

**Status: implemented.** Lambda and CI use Python `3.13`.

## What it is and what it does

Python is the programming language used for our request-handling logic and tests. It is also the planned language for FastAPI and Streamlit.

## Why and how we use it

Using one language across validation, risk calculations, and the interface reduces context switching. Currently, `services/lambda/handler.py` uses only the standard library to produce JSON responses and validate aggregate site records. It does not calculate risk or store submissions.

## Small example

```powershell
python -m unittest discover -s services/lambda -p 'test_*.py' -v
```

This runs our local request-validation tests. Match local development to Python 3.13 when possible; a different locally installed version does not change Lambda's configured runtime.

# AWS Lambda

**Status: deployed.** Function: `clinical-trial-site-risk-monitor-dev`.

## What it is and what it does

Lambda runs application code on demand without us operating an application server for that function.

## Why and how we use it

It is the request-handling layer behind API Gateway. The deployed Python handler supports health checks and validates one submitted site record. Terraform packages `handler.py` at the ZIP root and sets the entry point to `handler.lambda_handler`.

The function has 128 MB of memory and a 3-second timeout. Its execution role permits writing its own logs, not reading S3 state or accessing Snowflake or Bedrock. Forwarding requests to the planned risk service remains future work.

## Small example

```text
GET /health -> Lambda -> 200 with status "ok"
POST /site-assessments -> Lambda -> valid record or validation error
```

The Lambda timeout is an upper limit, not how long every request takes.

# Amazon API Gateway HTTP API

**Status: deployed.** Defined in `infrastructure/modules/lambda/api.tf`.

## What it is and what it does

API Gateway exposes HTTPS routes and connects requests to Lambda. We selected the HTTP API product for our initial two routes.

## Why and how we use it

It provides an authenticated endpoint for the future Streamlit server without exposing a Lambda function URL. Both routes require AWS IAM authorization. The development stage has rate/burst throttling and access logs.

An HTTP API still uses HTTPS. AWS enforces the `TLS_1_2` policy, which supports TLS 1.2 and 1.3. AWS's separate REST API product offers additional capabilities; choosing HTTP API did not remove TLS.

## Small example

```http
POST /dev/site-assessments
Content-Type: application/json
```

The request must also be SigV4-signed. See the [API guide](api.md) for the complete body and authentication requirements. POST currently returns `status: validated`, not a risk assessment.

[AWS API product comparison](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-vs-rest.html) and [HTTP API TLS policy](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-ciphers.html).

# AWS IAM and Permissions Boundaries

**Status: implemented and deployed.**

## What they are and what they do

IAM roles and policies control which identities may perform which AWS operations. A permissions boundary limits a role's maximum permissions; it does not grant permissions on its own.

## Why and how we use them

We separate responsibilities rather than sharing one powerful role:

- The Lambda execution role writes streams/events only in its own log group.
- The GitHub deployment role manages the named development resources and their state.
- The Lambda boundary prevents CI from granting the function permissions beyond its approved logging access.
- A separate caller role for Streamlit is planned; the UI should not use the deployment role.

## Small example

```text
Lambda execution role: logs:PutLogEvents -> its own log streams
Deployment role: iam:PassRole -> only the Lambda execution role, only to Lambda
```

CI's API management permissions use our exact API ID. The operator-managed Terraform stack controls CI's permissions; CI cannot modify its own access.

# OpenID Connect and AWS STS

**Status: implemented and verified in GitHub Actions.**

## What they are and what they do

OpenID Connect (OIDC) lets GitHub present a verifiable workflow identity. AWS Security Token Service (STS) exchanges an accepted identity for temporary role credentials.

## Why and how we use them

The workflow does not need long-lived AWS access keys stored as GitHub secrets. Our trust policy accepts the STS audience and exact subjects for this repository's `main` branch, supporting GitHub's legacy and immutable-ID subject formats.

## Small example

```text
GitHub main-branch job -> OIDC token -> STS -> temporary deployment credentials
```

The token establishes identity; IAM policies still determine permissions. Pull-request jobs have no OIDC permission and do not access AWS.

[GitHub's AWS OIDC guide](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws).

# AWS Signature Version 4

**Status: implemented for API authentication and smoke tests.**

## What it is and what it does

Signature Version 4, or SigV4, signs an AWS request using credentials. AWS verifies the signature and checks the caller's IAM permissions.

## Why and how we use it

Our API routes use `AWS_IAM`, so an HTTPS request alone is insufficient. The workflow signs API smoke tests with its temporary deployment credentials. A future Streamlit server will sign requests using its own role.

## Small example

```text
Signed GET /health with execute-api:Invoke permission -> 200
Unsigned GET /health -> 403
```

HTTPS protects data in transit; SigV4 authenticates the caller. Temporary credentials also require the session token header.

# Git and GitHub

**Status: in use.** Repository: `rohitjain2021/clinical-trial-site-risk-monitor`.

## What they are and what they do

Git tracks versions of files. GitHub hosts the repository and supports pull requests, reviews, and automation.

## Why and how we use them

Application code, infrastructure, and documentation change together on branches and are reviewed before merging into `main`. This preserves a history of what changed and why.

## Small example

```powershell
git status
git diff
```

These show pending changes. A commit saves a local version; pushing publishes it to GitHub; merging integrates a branch. None of those terms means that an AWS deployment has necessarily occurred.

# GitHub Actions

**Status: implemented.** Workflow: `.github/workflows/lambda.yml`.

## What it is and what it does

GitHub Actions is our CI/CD service. A workflow starts jobs on runners when repository events occur.

## Why and how we use it

It runs our checks and deployment commands consistently in the same service that hosts the code:

- Pull request: Python tests, formatting, Terraform validation, and mocked security tests.
- Push to `main`: those checks plus an AWS deployment plan.
- Manual run on `main` with `deploy` checked: plan, apply, and live verification.

Jobs use Ubuntu `24.04`. Tool setup pins Terraform and Terragrunt versions. Actions are pinned to commit SHAs; JavaScript-based setup actions use Node 24. Node is their runtime, not our application's language.

## Small example

```text
Run workflow on main, deploy unchecked -> review a plan
Run workflow on main, deploy checked -> plan and deploy
```

The manual checkbox is our current deployment approval, not a separate required-reviewer environment gate. See the [CI/CD guide](cicd.md).

[Official GitHub Actions guide](https://docs.github.com/en/actions/get-started/understand-github-actions).

# Amazon S3 and Terraform State Locking

**Status: deployed and used by application infrastructure.**

## What it is and what it does

S3 stores objects. In this project it stores Terraform state: the record connecting resource definitions to deployed infrastructure. Native S3 lock files prevent concurrent Terraform state updates.

## Why and how we use it

Our computer and CI must share state. The bucket is `clinical-trial-site-risk-monitor-tfstate-dev-<AWS_ACCOUNT_ID>`, with encryption, versioning, public-access blocking, disabled ACLs, and an HTTPS-only policy.

Application units have separate state keys. The bucket's own bootstrap stack deliberately retains local state, which needs secure backup. This bucket does not store trial-site submissions.

## Small example

```text
dev/lambda/terraform.tfstate
dev/lambda/terraform.tfstate.tflock
dev/github-actions/terraform.tfstate
```

Our backend sets `use_lockfile = true`; no DynamoDB table is used. Do not commit state files or credentials to Git.

[Terraform S3 backend documentation](https://developer.hashicorp.com/terraform/language/backend/s3).

# Amazon CloudWatch Logs

**Status: deployed and verified.**

## What it is and what it does

CloudWatch Logs collects logs from the function and API so we can investigate failures and observe execution behavior.

## Why and how we use it

Lambda platform reports show execution duration, billed duration, initialization time, and memory use. API access logs record request IDs, route keys, and HTTP status codes. Both groups have 14-day retention; our handler does not log request bodies.

## Small example

```text
Lambda REPORT: Duration 1.71 ms, Billed Duration 2 ms, Max Memory Used 32 MB
API access log: routeKey POST /site-assessments, status 200
```

The Lambda numbers above are one observed warm test, not a performance guarantee. Full API round-trip time includes additional network and gateway time. Alerts and dashboards remain planned.

# FastAPI

**Status: implemented and tested locally; not deployed.**

## What it is and what it does

FastAPI is a Python framework for building APIs, with typed request models and generated API documentation.

## Why and how we plan to use it

It hosts the risk-calculation service separately from Lambda. `services/risk_service/app.py` exposes health and assessment routes and reuses the prototype calculator. The app is tested locally with representative inputs. Lambda integration and deployment through the planned load balancer remain future work. See the [local service guide](risk-service.md).

## Small example

```text
Site metrics -> FastAPI service -> risk level and specific contributing reasons
```

The current `status: validated` Lambda response is not this future assessment result. Risk thresholds and service routes have not been finalized.

[Official FastAPI documentation](https://fastapi.tiangolo.com/).

# Streamlit

**Status: planned in this repository.**

## What it is and what it does

Streamlit is a Python framework for interactive data applications.

## Why and how we plan to use it

It will give the clinical operations team a web interface to upload aggregate site data, review sites, and inspect risk results and explanations. Its server will authenticate to our API with a dedicated role. Hosting, upload handling, and interface code still need implementation.

## Small example

```text
User selects a CSV -> Streamlit validates rows -> server submits records -> results table
```

That is a planned flow. The current API accepts one JSON record, not CSV/Excel files or batches. Files in the separate Equipment_SME project are not this project's Streamlit implementation.

[Official Streamlit documentation](https://docs.streamlit.io/).

# Docker and Container Images

**Status: image built and tested locally; registry publishing and EKS deployment remain planned.**

## What it is and what it does

Docker provides tooling to build and run container images: packages containing an application and its runtime dependencies.

## Why and how we plan to use it

We need a consistent FastAPI package for local testing and Kubernetes deployment. `services/risk_service/Dockerfile` uses Python 3.13, runtime requirements, and a non-root user. Its build context excludes tests, virtual environments, and private settings. Local container checks passed for health, risk assessment, invalid input, and the restricted runtime. See the [local container guide](container.md) for build and test commands and validation results.

## Small example

```text
FastAPI source + pinned dependencies + image build instructions -> versioned image
```

Our current Lambda uses a ZIP package, not a container image. Choosing containers for FastAPI does not require changing Lambda's packaging.

[Official Docker overview](https://docs.docker.com/get-started/docker-overview/).

# Amazon Elastic Container Registry (ECR)

**Status: planned supporting service; no repository is provisioned yet.**

## What it is and what it does

ECR is a container image registry: a place to store and retrieve versioned application images.

## Why and how we plan to use it

It is the proposed registry for the FastAPI image that EKS will run. Terraform will define the repository and access controls; CI will build and publish images once container deployment is implemented.

## Small example

```text
CI builds image for commit abc123 -> ECR stores image -> EKS pulls that image
```

The final repository name and image-versioning policy have not been defined.

# Kubernetes

**Status: planned; no cluster workloads are deployed.**

## What it is and what it does

Kubernetes manages containerized workloads. A Deployment describes application replicas, pods run the containers, and a Service provides a stable way to reach them.

## Why and how we plan to use it

Our target architecture runs FastAPI replicas with health checks and controlled updates. Kubernetes will maintain the desired replicas and replace failed pods. It will not determine clinical risk; that remains Python application logic.

## Small example

```text
Desired replicas: 3
One FastAPI pod fails -> Kubernetes creates a replacement
```

Three replicas are illustrative, not an existing deployment or a finalized capacity decision. Workload configuration must be versioned and managed as code.

[Official Kubernetes concepts](https://kubernetes.io/docs/concepts/).

# Amazon Elastic Kubernetes Service (EKS)

**Status: planned; no EKS infrastructure is provisioned.**

## What it is and what it does

EKS is AWS's managed Kubernetes service. It provides the cluster platform on which our container workloads can run.

## Why and how we plan to use it

Our architecture selects Kubernetes on AWS for hosting the risk service. Terraform/Terragrunt will define cluster infrastructure, compute, networking, and permissions. Workload deployment and CI integration still need design and implementation.

## Small example

```text
EKS cluster -> Kubernetes Deployment -> FastAPI pods
```

Kubernetes is the orchestration system; EKS is the managed service hosting it. Cluster size, Kubernetes version, and compute mode are not selected yet.

[Official EKS overview](https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html).

# Application Load Balancer (ALB)

**Status: planned; Lambda does not call a load balancer yet.**

## What it is and what it does

An ALB routes HTTP/HTTPS requests to registered healthy targets.

## Why and how we plan to use it

The target architecture uses it between Lambda and the FastAPI service so callers do not need to know individual pod addresses. Listener configuration, target registration, health checks, and private connectivity will be defined through infrastructure as code.

## Small example

```text
Lambda request -> ALB -> healthy FastAPI target
```

Private network access, certificates, and any required Kubernetes controller have not been configured. The diagram shows the intended destination architecture, not an active connection.

[Official ALB introduction](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/introduction.html).

# Amazon VPC, Subnets, and Security Groups

**Status: application-specific networking is planned.**

## What they are and what they do

A VPC is a logical network. Subnets divide its address space, and security groups control allowed traffic for attached resources.

## Why and how we plan to use them

They will connect Lambda, the load balancer, and EKS while limiting permitted network paths. We must design private access, outbound service access, and security-group rules before deploying those components. Terraform/Terragrunt will manage the configuration.

## Small example

```text
Lambda security group -> permitted service port -> internal ALB -> FastAPI targets
```

This is illustrative. Lambda is not currently attached to a project VPC, and no project EKS/ALB network has been created.

# Snowflake and SQL

**Status: planned; submissions are not saved today.**

## What they are and what they do

Snowflake is a managed data platform for storing and querying data. SQL is the language we plan to use for table definitions and queries.

## Why and how we plan to use them

We need durable site records and assessment history so users can revisit results and compare operational performance. Snowflake is the selected target in the architecture. Schemas, service authentication, roles, and integration code are not implemented yet.

## Small example

```sql
-- Illustrative future query; this table does not exist yet.
SELECT site_id, risk_level
FROM site_assessments
WHERE risk_level = 'High';
```

The state bucket is unrelated to this application data store. A successful POST currently does not create a Snowflake row.

[Official Snowflake concepts](https://docs.snowflake.com/en/user-guide/intro-key-concepts).

# Amazon Bedrock

**Status: planned; no model is selected or invoked.**

## What it is and what it does

Bedrock provides managed access to foundation models for generative AI applications.

## Why and how we plan to use it

It will turn calculated risk factors into readable operational explanations. We should implement and test risk rules first, then ground generated explanations in those results. Model choice, prompts, permissions, data handling, and evaluation remain to be defined.

## Small example

```text
Calculated factors: enrollment shortfall, schedule delay, unresolved issues
Planned explanation: explain how those measured factors contributed to the classification
```

This does not mean the current API performs AI analysis. An explanation must not invent facts or replace the agreed risk calculation.

[Official Bedrock overview](https://docs.aws.amazon.com/bedrock/latest/userguide/what-is-bedrock.html).

# Supporting Development and Verification Tools

These tools support development and delivery; they are not additional application services.

| Tool or format | What it does | Why/how we use it | Small example |
|---|---|---|---|
| AWS CLI | Calls AWS APIs from a terminal | Verify identity, inspect configuration, invoke Lambda, and read logs; resource changes stay in Terraform | `aws sts get-caller-identity` |
| WinGet | Windows package manager | Install the local Terraform and Terragrunt executables | `winget --version` |
| PowerShell | Windows shell | Run local setup, testing, and infrastructure commands | `terragrunt --version` |
| Bash | Shell used by Linux CI runners | Run workflow validation, installation, and deployment steps | `set -euo pipefail` makes failures stop scripts |
| curl | HTTP command-line client | Test signed API requests and download checksum-verified tools | Unsigned health request returns 403 |
| JSON | Structured data format | Site submissions and Lambda response bodies | `{"status":"validated"}` |
| HCL | Configuration language used by Terraform/Terragrunt | Describe resources and environment settings | `log_retention_days = 14` |
| YAML | Structured configuration format | Define GitHub Actions; planned Kubernetes manifests may also use it | `runs-on: ubuntu-24.04` |
| Python unittest | Standard-library test framework | Test valid and invalid request contracts without AWS | `python -m unittest discover -s services/lambda` |
| Terraform test with mock providers | Exercises infrastructure configuration without creating live resources | Verify scoped IAM grants, authorization, throttling, and retention | `terragrunt --working-dir infrastructure/live/dev/lambda test` |
| actionlint | GitHub Actions workflow validator | Used locally to check workflow syntax and expressions; not currently a CI step | Validate `.github/workflows/lambda.yml` |
| Markdown | Plain-text documentation format | Write the README and these linked guides | `[API guide](api.md)` |

# How the Pieces Fit Together

**Working today:**

```text
Signed API request -> API Gateway HTTP API -> Python Lambda validation -> JSON response
GitHub Actions -> OIDC/STS -> Terragrunt -> Terraform -> AWS resource APIs
Terraform state -> S3, with locking
Lambda/API logs -> CloudWatch Logs
```

**Planned application flow:**

```text
Streamlit -> API Gateway -> Lambda -> ALB -> FastAPI on EKS
                                             |-> Snowflake data/history
                                             |-> Bedrock explanations
```

See the [setup guide](setup.md), [API guide](api.md), [CI/CD guide](cicd.md), and the README's Things to Do checklist for implementation details and remaining work. All snippets describing planned components are illustrative; they are not instructions to deploy missing resources manually.
