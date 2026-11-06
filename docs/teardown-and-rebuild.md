# Testing Environment Teardown and Rebuild

## Purpose and Status

Remove the clinical trial project's running backend when it is not needed, then recreate it from the existing Terraform and Terragrunt configuration before a demonstration. This is a manual operator procedure, with no idle timer or scheduled deletion.

This runbook covers the explicitly requested teardown and future rebuild. Check live resources and state before every execution. It applies only to `clinical-trial-site-risk-monitor`, not the separate serverless API metering project.

## Teardown Record: November 6, 2026

Teardown completed through reviewed saved Terraform plans: Lambda was disconnected; the ALB unit removed 12 resources, the application unit removed five resources, and the EKS unit removed 22 resources. All applies succeeded, and each backend state has zero remaining managed resources.

AWS verification confirmed the EKS cluster and worker group are absent, the worker instance is terminated, its original root disk is deleted, and the ALB, target group, dedicated ALB security groups, cluster security group, and cluster network interfaces are absent. No cluster-tagged disks or worker Elastic IP allocations remained. Default networking, the Terraform backend, the published ECR image, Lambda/API, and the SNS topic with its confirmed email subscription were retained. Lambda is active, has no backend URL or VPC attachment, and its liveness invocation returned `200`.

The GitHub repository and application source remain available. A valid synthetic assessment invocation returned the expected disconnected-backend `503`; Streamlit's live backend assessments are offline until the rebuild steps below are completed. Retained storage and services may still incur charges; the continuous EKS/worker/ALB resources have been removed. Verify later billing separately because usage reporting can lag.

The last known working published image commit is `fefff54c5db15efddc8a6df509f78b1a3c4fe056`. Its image was verified in the retained ECR repository before teardown. Verify it still exists before rebuilding; otherwise publish a reviewed replacement. Private resource inventory and saved plans remain ignored locally; encrypted state remains in S3.

## Scope

| Remove through Terraform | Retain for rebuilding |
|---|---|
| Internal ALB, listener, target group, worker attachment, and dedicated ALB access groups/rules | Existing default VPC, subnets, routes, and unrelated resources |
| FastAPI Kubernetes namespace, workload, Service, service account, and verification jobs | GitHub source, workflows, and private configuration |
| EKS control plane, managed worker group and its EC2 capacity, launch template, add-ons, cluster IAM resources, OIDC provider, and cluster log group | Terraform state bucket, state history, and deployment/bootstrap IAM permissions |
| Worker root disks configured to delete on termination and EKS-managed network resources as AWS releases them | ECR repository and the selected image digest/commit |
| Lambda backend URL and VPC attachment, by updating the Lambda unit | Lambda/API Gateway, their logs, Streamlit app and its API identity, SNS topic and confirmed email subscription |

This removes the main continuous EKS, worker, and ALB costs. Retained image/log/state storage and retained services can still incur storage or usage charges; this is not a zero-cost account shutdown. The EKS unit deletes its cluster log group: preserve any logs needed for investigation before applying its destroy plan. If persistent volumes or other retained data are found, decide their handling before proceeding.

## Before Teardown

1. Use a clean, reviewed checkout containing the deployed configuration. Pause manual deployment runs and confirm no GitHub workflow or local Terraform apply is active. Do not run deployment and teardown concurrently.
2. Use the approved operator AWS identity in `us-east-1`. Verify the intended account privately. Keep identifiers, credentials, state, and plan files outside Git.
3. Inspect live resources against the `dev/alb`, `dev/demo-app`, and `dev/eks` Terraform states. Record worker instance/volume IDs and ALB network dependencies privately for the final cleanup check. Also check for project-owned disks, addresses, or other resources outside those states; investigate ownership before deleting anything.
4. Record a known working published image's full commit SHA and digest, and confirm that image still exists in ECR. Keep the image available until rebuilding is finished.
5. Preserve ignored deployment/operator configuration and required GitHub secrets securely. Confirm the operator's current public `/32` is allowed to access Kubernetes. ALB and app removal require the cluster to remain reachable.
6. Review the module's Kubernetes version against currently supported regional versions before a future rebuild. Review IAM boundaries, model access, Spot availability, and operator access then as well; retained configuration is not a guarantee of future availability.

## Teardown Order

### 1. Disconnect Lambda

Run **Actions -> Lambda CI and dev deployment -> Run workflow** on `main`:

- **deploy:** checked.
- **disconnect_backend:** checked.
- **publish_image:** unchecked.

Wait for success. This updates Terraform-managed Lambda configuration, retaining the API while removing the backend URL and VPC attachment. Check signed health, assessment `503`, and unsigned denial as described in the [Lambda guide](lambda-backend.md#explicit-disconnect-before-teardown).

Wait until AWS releases Lambda's interfaces using the dedicated ALB client security group. Do not delete that group, its interfaces manually, or Lambda's execution permissions while release is pending.

### 2. Review and Remove Each Backend Unit

Run from the repository root with operator credentials. Plan and apply **one unit at a time**, in this order:

| Order | Unit | Why this order matters |
|---|---|---|
| 1 | `alb` | Removes its Kubernetes verification job, worker attachment, and load balancer dependencies while EKS and the app exist. |
| 2 | `demo-app` | Removes Kubernetes resources through the still-running cluster API. |
| 3 | `eks` | Removes workers and the cluster after their consumers are gone. |

For the first unit:

```powershell
New-Item -ItemType Directory -Force infrastructure/state | Out-Null
$backendUnit = 'alb'
$destroyPlan = Join-Path $PWD "infrastructure/state/$backendUnit-destroy.tfplan"
terragrunt --working-dir "infrastructure/live/dev/$backendUnit" init -input=false
terragrunt --working-dir "infrastructure/live/dev/$backendUnit" plan -destroy "-out=$destroyPlan"
```

Inspect the plan privately. It must contain only the intended unit's owned resource deletions, with no unrelated resource changes or shared network deletion. Stop on errors, unexpected resources, drift, or missing dependencies. After review and authorization to delete that unit, apply its exact saved plan:

```powershell
terragrunt --working-dir "infrastructure/live/dev/$backendUnit" apply $destroyPlan
```

Confirm success before repeating the plan/review/apply sequence with `$backendUnit = 'demo-app'`, then `$backendUnit = 'eks'`. Each needs its own newly generated saved plan. Check every command's exit status; never continue after a failure or reuse an obsolete plan.

Do not run an environment-wide destroy. Do not remove the state backend or state files, bypass locking, or remove resources from state to conceal a failed deletion. Do not use the deployment workflow for destruction: its safety checks reject infrastructure deletion and replacement. No teardown workflow is introduced by this plan.

### 3. Verify Cleanup

Verify through AWS that the project cluster and node group are absent, worker instances are terminated, and their root volumes and public IP allocations are released. Verify that the project ALB, listener, target group, attachment, and dedicated access groups are gone, and check for remaining project ENIs or unattached disks. Shared default networking must remain.

Inspect the three Terraform states for remaining managed resources and investigate any partial failure. Confirm the retained ECR image, Lambda/API, SNS subscription, and state backend remain available. Billing data can lag; resource absence is the immediate check, followed by a later billing review. Streamlit remains hosted but backend assessments are unavailable during this period.

## Rebuild Order

### 1. Restore Prerequisites

Use the reviewed source and supported tool/provider versions. Restore private local configuration and verify the retained state backend, GitHub OIDC roles, permissions boundaries, SNS topic/subscription, and ECR image. Update the operator's trusted `/32` if it changed. Review any changes in service versions, permissions, or availability before provisioning.

If the recorded image no longer exists, run **Lambda CI and dev deployment** on `main` with **publish_image** checked, **deploy** unchecked, and **disconnect_backend** unchecked. Wait for the image-publishing job to succeed and record that run's full 40-character image commit SHA.

### 2. Recreate EKS and FastAPI

Run **Actions -> Deploy EKS and risk service** on `main` with the full published **image_commit**, leaving **deploy** unchecked first to review the EKS plan. Then run with **deploy** checked to create EKS and deploy the app. The application plan follows creation of the cluster because it requires its outputs. The workflow checks plans before applying them and runs in-cluster HTTP verification.

Confirm a ready worker, a ready FastAPI replica, passing verification, and the expected Bedrock/SNS role and topic configuration. A recreated cluster has a new endpoint, certificate, and OIDC issuer; use fresh Terraform outputs, not saved cluster identifiers. See the [deployment guide](deployment.md).

### 3. Recreate the ALB

The ALB is a separate operator-run unit; the EKS workflow does not provision it. Ensure ignored `demo.local.hcl` references the chosen published image and a fresh verification run ID, and `eks.local.hcl` permits the operator's current access. Use the current dependencies from Terraform state.

```powershell
terragrunt --working-dir infrastructure/live/dev/alb init -input=false
$albPlan = Join-Path $PWD 'infrastructure/state/alb-rebuild.tfplan'
terragrunt --working-dir infrastructure/live/dev/alb plan "-out=$albPlan"
```

Review the saved plan before applying:

```powershell
terragrunt --working-dir infrastructure/live/dev/alb apply $albPlan
```

Wait for the target to become healthy and the ALB verification job to pass. See the [ALB guide](alb.md). Its recreated DNS name and security-group IDs can change.

### 4. Reconnect Lambda and Test Streamlit

Run **Lambda CI and dev deployment** on `main` with **deploy** checked, **disconnect_backend** unchecked, and **publish_image** unchecked. The workflow discovers the new ALB settings from state and applies them through Terraform.

Verify authenticated health and synthetic High/Medium/Low assessments, invalid-input rejection, and unsigned denial. Submit a synthetic report in Streamlit, check the AI explanation and SNS email, and inspect CloudWatch SNS delivery metrics. If the retained public API and its identity have not changed, Streamlit Secrets do not need changing. Otherwise update them privately using the new Terraform outputs.

Recreation is complete only after these checks pass. Allow provisioning and troubleshooting time before a demonstration; no fixed rebuild duration is guaranteed. Resources remain running until another explicitly requested teardown.
