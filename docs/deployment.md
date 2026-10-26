# EKS and FastAPI Deployment

Use **Actions → Deploy EKS and risk service → Run workflow** on `main` after this change is merged. This replaces the disposable Start/Stop workflow.

## Plan

Leave **deploy** unchecked and choose a full commit SHA already published to ECR. The workflow resolves its immutable digest, writes private settings on the runner, and saves and checks an EKS Terraform plan. The log lists resource addresses and actions without publishing raw plans or state.

A plan-only run does not apply infrastructure or contact Kubernetes. The application plan follows EKS provisioning because it requires the cluster's outputs.

## Deploy

Select **deploy** to provision or update EKS through Terragrunt and Terraform, then deploy the existing private FastAPI container. The workflow checks each saved plan before applying it and waits for the deployment and its in-cluster HTTP verification job. The checks cover health, a synthetic High-risk assessment, and invalid-input rejection.

The workflow uses the existing default VPC, two existing subnets, one Spot worker, the private ECR image, explicit IAM access, and scoped permissions boundaries. It authenticates with GitHub OIDC on `main`; no stored AWS access keys are required. The existing encrypted operator ARN and `/32` secrets remain required.

Resources stay provisioned after success or failure. There is no Start/Stop choice, scheduled shutdown, or automatic destruction on failure. EKS and its workers continue to incur charges while provisioned. See the [EKS guide](eks.md) for the existing cost estimate and explicit operator cleanup.

## Architecture and Current Scope

The planned request path remains Streamlit → API Gateway → Lambda → ALB → EKS/FastAPI, with ECR supplying the image and Terraform/Terragrunt managing infrastructure. ALB, Lambda-to-FastAPI integration, hosted Streamlit integration, Snowflake, and Bedrock remain separate work. This workflow does not claim that the complete application is deployed.

The first deployment attempts exposed missing custom-template launch permissions and a missing `iam:GetRole` permission for `AWSServiceRoleForAmazonEKSNodegroup`. Those permissions are defined in the GitHub-access Terraform module. Launches are restricted to the selected subnets, project-tagged template, and `t3.medium`; the service-role read targets its two exact ARN forms. Before the role exists, the lookup uses the role name without a path; after creation, it uses the service-linked path. Both reads are needed for first-time provisioning, and neither grants role modification. EKS creates the service-linked role as part of managed worker provisioning; see [AWS service-linked role behavior](https://docs.aws.amazon.com/eks/latest/userguide/using-service-linked-roles-eks-nodegroups.html).

Existing IAM resource names, Terraform addresses, the `dev/eks` and `dev/demo-app` state keys, and the Kubernetes application module are retained to avoid replacing infrastructure merely to rename it. The role's legacy `github-demo` name does not provide a Start/Stop lifecycle. The Lambda deployment role keeps its separate scope. Concurrency also retains its existing group so deployment cannot overlap an old lifecycle run.

## Required Networking Image

The VPC CNI also runs `aws-eks-nodeagent`, which pulls `amazon/aws-network-policy-agent` from the AWS-owned regional ECR registry. Both the worker role and its operator-managed permissions boundary must allow read-only pulls from that exact repository. Missing it caused `ImagePullBackOff` for the agent and pod sandbox network setup failures even though the worker group was active. The policies retain explicit repositories instead of granting general ECR image access. See [AWS network policy agent](https://github.com/aws/aws-network-policy-agent).

## Failed or Interrupted Deployment

Inspect the error and rerun after fixing its cause. Failure leaves resources and Terraform state available for diagnosis. Deployment plans reject infrastructure deletion, replacement, and resources outside the existing project allowlist. Replacing the completed HTTP verification job is the sole permitted replacement.

Cancellation can interrupt state persistence. Before retrying, verify the previous runner is finished, recover only exact ownership-checked resources into their original Terraform addresses, and review a new plan. Release a stale lock only after confirming its owner is no longer running. Do not disable state locking, delete state, or manually delete AWS resources to hide a conflict.

## Validation

Local tests cover main-only execution, plan-only behavior, the project resource allowlist, rejection of infrastructure deletion/replacement, repeatable HTTP verification, and leaving resources intact on failure. Mocked Terraform tests cover IAM scope, EKS hardening, and the private application runtime. A successful live deployment through the replacement workflow still requires merging and running it on `main`.
