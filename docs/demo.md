# Start and Stop the Development Demo

**Status: workflow merged; IAM bootstrap and encrypted operator settings configured. Supervised cloud testing exposed launch-permission and interrupted-state cleanup issues. Their fixes are under validation; a successful complete Start/Stop cycle is still required. Check Actions for current running resources.**

Use **Actions → Start or stop demo → Run workflow** on `main`. Choose `start` before a session and `stop` afterward. The workflow is manual only, defaults to Stop, and serializes operations so Start and Stop cannot overlap. It does not run when you push code or open a pull request.

## What Start Does

1. Checks that the selected full commit SHA exists in the project's ECR repository, then resolves its immutable image digest. The default is the first image already verified in ECR; publishing a newer image remains a separate workflow.
2. Creates or updates only the EKS unit in the existing default VPC: one Spot worker, core add-ons, explicit operator/workflow access, and the project's service roles and logs. It rejects unexpected resource addresses and infrastructure replacements.
3. Waits for Kubernetes access, then applies a separate Terraform application unit: a project namespace, one FastAPI Deployment, a private ClusterIP Service, and a verification Job. The non-root container runs with a read-only filesystem, resource limits, no Kubernetes service-account token, and no elevated capabilities.
4. Waits for deployment readiness and real in-cluster HTTP tests: health, a synthetic High-risk assessment, and invalid-input rejection. Each Start creates a fresh verification Job.

This demonstrates the FastAPI component only. Streamlit, ALB, Lambda-to-service integration, Snowflake, and Bedrock remain separate project work. There is no public demo URL yet.

After Start succeeds, an authorized operator can privately inspect FastAPI from their allowed IP with `kubectl`:

```powershell
aws eks update-kubeconfig --region us-east-1 --name clinical-trial-site-risk-monitor-dev-eks
kubectl -n clinical-trial-site-risk-monitor-demo port-forward service/clinical-trial-risk-service 8000:8000
```

Then open `http://127.0.0.1:8000/docs` locally. Keep kubeconfig, endpoints, and local access settings private. This reads cluster configuration and forwards a local port; it creates no AWS resources. Operator credentials must match the configured access entry and the current IP must match its `/32` allowlist.

## What Stop Does

1. Reads only the two demo state keys. If application resources exist, it updates only the existing cluster's API allowlist for the new GitHub runner; its targeted plan must not create any resources.
2. Destroys the Terraform application unit while Kubernetes is available, then destroys the EKS unit. Destroy plans are checked against a fixed resource-address allowlist and may only delete owned resources.
3. Confirms empty demo states, an absent EKS cluster and its three service roles, and no remaining project-tagged worker instances or root disks. A repeated Stop is safe; it does not recreate an absent cluster.

The existing default VPC/subnets/routes, ECR repository/images, Lambda/API, GitHub IAM bootstrap, and Terraform backend remain. Retained resources can still have their own costs. The current application creates no load balancer or persistent volume. If those are added later, their cleanup must be added and tested before describing Stop as covering them.

## Charges and Failures

See the [EKS cost estimate](eks.md#estimated-running-cost). A successful Start leaves resources running until you run Stop. **There is no automatic timer or idle shutdown.** Include creation and deletion time in your budget; the workflow timeout does not stop AWS billing.

A failed Start attempts the same scoped cleanup before failing. If cleanup fails, credentials expire, or a run is cancelled/times out, run Stop again and inspect AWS. Do not assume cancellation or a failed workflow removed resources. Spot capacity may be unavailable or interrupted; allow time before a demonstration and test readiness.

## One-Time Setup

Terraform in the operator-managed GitHub-access unit defines the main-only `clinical-trial-site-risk-monitor-dev-github-demo` role, scoped inline policy, and `clinical-trial-site-risk-monitor-dev-eks-nodes-boundary`. These three resources were applied through a reviewed saved plan on October 25, 2026; AWS Access Analyzer returned no policy findings and a follow-up plan reported no changes. This bootstrap creates no cluster or EC2 workers.

The role cannot edit itself or its boundaries. It can write only `dev/eks/terraform.tfstate` and `dev/demo-app/terraform.tfstate` plus their locks, and read the ECR dependency state. Repository creation/deletion, network creation/deletion, ECR image writes, and access to other application stacks are not granted. Discovery actions and AWS service roles require documented broader resource scopes. IAM/provider resources with generated identifiers require exact project/environment/name tags for changes.

AWS does not support resource-level authorization for `eks:CreateCluster`. That action therefore uses `Resource: "*"` with conditions requiring the development region, exact demo tags, Kubernetes `1.36`, standard support, API authentication, explicit admin entries, and private/restricted-public endpoint configuration. Subsequent cluster operations are scoped to the named demo ARN. The runner script separately rejects unexpected Terraform addresses and infrastructure replacement. See [AWS EKS authorization](https://docs.aws.amazon.com/service-authorization/latest/reference/list_eks.html).

The workflow reuses the existing encrypted account and state-bucket secrets and also requires:

| GitHub Actions secret | Value | Status |
|---|---|---|
| `PROJECT_EKS_ADMIN_PRINCIPAL_ARN` | Existing operator IAM user or role ARN | Configured; secret metadata verified |
| `PROJECT_EKS_ADMIN_CIDR` | Operator's current public IPv4 address with `/32` | Configured; secret metadata verified |

Keep those values outside source control. They identify the AWS operator/account and network access address. Local examples stay in ignored `eks.local.hcl`; the workflow writes ignored settings on its temporary runner. A runner's public `/32` is discovered for each operation, added alongside the operator's `/32`, and masked. If the operator's IP changes, update the encrypted setting before a session.

The two operator settings were encrypted with GitHub's public key and uploaded with explicit user authorization on October 25, 2026. Only secret metadata was read back; plaintext values are not in source or documentation.

Stop has passed against the development environment. Start has been attempted, but a complete successful rollout and Stop cycle must pass before relying on this flow for a demonstration.

### Recovery after an interrupted apply

Cancellation can leave AWS resources that are missing from Terraform state. In the first supervised cycle, the CNI role, its policy attachment, and its OIDC provider remained after an interrupted apply. A later Start collided with the existing role. The operator verified the exact project tags and imported those three resources into their original EKS Terraform addresses, reviewed a destroy-only saved plan, and applied it through Terragrunt. No shared network or application resources were deleted.

Do not delete such resources manually or remove more state to hide the conflict. Inspect ownership privately, recover the resources into the matching Terraform addresses, and review the cleanup plan. Stop now checks the three named service roles directly in AWS and fails if a role exists or its absence cannot be verified. This catches role leftovers even when the EKS state is empty.

## Validation

### Custom launch-template permissions

EKS checks a custom worker launch template using the caller's EC2 permissions. The first live Start exposed missing `ec2:RunInstances` and `ec2:DescribeRouteTables` permissions: the control plane became active, but worker creation failed and CoreDNS waited without nodes.

The operator-managed GitHub-access stack now includes managed policy `clinical-trial-site-risk-monitor-dev-demo-node-launch`. Launch inputs are limited to the selected default subnets and regional resources, instances are limited to `t3.medium`, and the launch template must carry the exact demo project/environment/name tags. Instance and disk tagging is allowed only during `RunInstances` with the project's tags. Route-table discovery is read-only and region-restricted. The fix does not grant network deletion or unrestricted EC2 administration.

This policy is separate from worker-node runtime permissions and fits outside IAM's aggregate inline-policy quota. See [AWS's EKS custom-template requirements](https://docs.aws.amazon.com/eks/latest/userguide/launch-templates.html) and [EC2 launch-template authorization examples](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ExamplePolicies_EC2.html).

Terraform's IAM role deletion also requires `iam:ListInstanceProfilesForRole`. The demo role grants that read action only on its three service-role ARNs so Stop can complete role cleanup after deleting EKS.

Eleven Python lifecycle safety tests cover deletion scope, creation rejection during Stop, no infrastructure replacement during Start, application-first cleanup, repeated Stop, orphan-role detection, and denied cleanup reads. Six mocked Terraform runs cover the EKS configuration, application hardening/digest pinning, main-only IAM trust, scoped state, and bounded role creation. Both workflow files pass actionlint. The verification Job's exact HTTP-check code also passed against a local hardened Docker container, with its service URL redirected to the local test port.

AWS IAM simulation confirmed tagged demo creation and deletion of the named cluster are allowed, while untagged creation, deletion of another cluster or a VPC, editing the demo role's own policy, and image pushes are denied. AWS Access Analyzer reported no findings for the corrected policy. These checks do not substitute for a real EKS rollout and cleanup test.
