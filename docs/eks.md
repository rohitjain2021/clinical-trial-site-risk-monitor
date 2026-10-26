# EKS Development Plan

**Status: EKS and its worker group are active, with FastAPI deployed privately. The corrected HTTP verification job passed health, assessment, cache-control, and invalid-input checks after a reviewed Terraform job replacement. The deployment workflow must be rerun after merging that verification fix. Resources remain provisioned until explicit teardown.**

Terraform defines the cluster in `infrastructure/modules/eks`; Terragrunt supplies development configuration in `infrastructure/live/dev/eks`. The cluster is named `clinical-trial-site-risk-monitor-dev-eks`. Supporting roles, worker nodes, root disks, launch template, and log group use the same project prefix.

## Existing Network

The module reads the existing default VPC and its default subnets in `us-east-1a` and `us-east-1b` using Terraform data sources. It does not adopt or create VPCs, subnets, internet gateways, route tables, or subnet tags. These shared resources stay outside this stack's ownership and destruction plan.

Read-only AWS checks confirmed DNS support, DNS hostnames, internet-gateway routing, automatic public IPv4 assignment, and sufficient free addresses. Both selected zones support EKS. The module rejects the unsupported `use1-az3` zone ID, which maps to `us-east-1e` in this account, and requires two distinct zones with at least 16 free subnet addresses each. Recheck routing before a future apply if the shared network changes. See [EKS network requirements](https://docs.aws.amazon.com/eks/latest/userguide/network-reqs.html).

This development design uses public worker subnets and does not add a NAT gateway. A public worker address does not grant inbound access: EKS attaches its cluster security group, and no SSH key, remote-access rule, public application port, or load balancer is configured in this step.

## Cluster and Worker

- Explicit Kubernetes version `1.36`, with standard-support policy. Review the [version lifecycle](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html) before applying or upgrading; versions and add-ons require maintenance.
- One Spot `t3.medium` Amazon Linux 2023 worker; desired, minimum, and maximum size are one. Spot is discounted spare capacity, not free, and AWS can interrupt it or have no capacity available. No autoscaler is installed. A single worker is suitable for development, not high availability.
- Minimal worker update strategy replaces capacity without first scaling up for a rolling update; expect development downtime. Spot rebalancing/replacement can still temporarily overlap instances, so the desired count is not a hard billing cap.
- Encrypted 20 GiB gp3 root disk, deleted with its worker, with project tags on the instance and volume.
- IMDSv2 required, metadata hop limit one, and standard CPU credits to avoid surplus burst-credit charges.
- Private Kubernetes API access for workers; public API access restricted to explicitly configured operator `/32` addresses.
- Explicit operator and deployment-workflow access entries instead of an implicit creator-admin grant.
- API, audit, authenticator, controller-manager, and scheduler logs with 14-day retention.
- Managed VPC CNI, kube-proxy, and CoreDNS add-ons using versions compatible with the chosen Kubernetes minor. The plan resolves their current versions; inspect future version changes before applying.

The Kubernetes cluster and node IAM roles receive the AWS-managed EKS policies needed for their respective services. All three service roles require operator-managed permissions boundaries. The deployment workflow cannot edit those boundaries or its own permissions. The VPC CNI uses a separate IAM role restricted to the `kube-system/aws-node` service account, so worker-role credentials do not carry the CNI networking policy. These service-managed policies include discovery and networking actions that require broader AWS resource scopes; they are not administrator policies. See [node IAM roles](https://docs.aws.amazon.com/eks/latest/userguide/create-node-role.html) and [CNI service-account permissions](https://docs.aws.amazon.com/eks/latest/userguide/cni-iam-role.html).

Image-pull permissions are read-only and restricted to the project's ECR repository plus the five named core system-image repositories in [AWS's documented regional add-on registry](https://docs.aws.amazon.com/eks/latest/userguide/add-ons-images.html). The AWS-owned registry account ID in the module is public service metadata, not this project's account ID. Registry authentication uses a regional wildcard because ECR does not support repository scoping for that action. No image-push permissions are granted to workers.

## Private Operator Configuration

Copy `infrastructure/live/dev/eks/eks.example.hcl` to the ignored `eks.local.hcl`, then privately set an existing IAM user/role ARN and trusted public IPv4 `/32`. Do not use root or an STS assumed-role session ARN. Do not commit the local file or its values.

The local planning setup uses the current operator IAM principal and the public IPv4 address observed through AWS's check-IP service. Refresh that address if the network or VPN changes. Public source and documentation contain only examples.

## Plan Only

Use operator credentials for local review. The existing Lambda GitHub deployment role has not been granted EKS provisioning permissions; a separate main-only role provisions EKS and the application. Its one-time bootstrap lives in the GitHub-access Terraform unit. Terragrunt uses the existing encrypted, locked S3 backend with key `dev/eks/terraform.tfstate`. See the [deployment guide](deployment.md) before deployment.

From the repository root:

```powershell
terragrunt --working-dir infrastructure/live/dev/eks init -input=false
terragrunt --working-dir infrastructure/live/dev/eks validate
terragrunt --working-dir infrastructure/live/dev/eks plan -out=eks.tfplan
```

This step stops after plan review. Saved plans and state are private and ignored by Git. Operator ARNs, IP allowlists, endpoints, and security-group IDs must not appear in public documentation or artifacts. Inspect the resource list, version, CIDRs, and costs before authorizing an apply. Terraform does not calculate running costs.

## Estimated Running Cost

The cluster remains provisioned until an operator explicitly destroys it through Terraform. There is no guaranteed free worker or free EKS control plane; account credits or free-tier eligibility have not been verified. A stopped or removed worker does not stop the cluster's hourly charge.

Illustrative `us-east-1` costs checked October 25, 2026, using the current Spot prices for `t3.medium` in the selected zones. The monthly column shows the cost of accidentally leaving it running for 730 hours, with one worker and no credits:

| Component | Rate | Monthly estimate |
|---|---|---:|
| EKS standard-support control plane | $0.10/hour | $73.00 |
| One Linux `t3.medium` Spot worker | $0.0142–$0.0161/hour | $10.37–$11.75 |
| One worker public IPv4 address | $0.005/hour | $3.65 |
| One 20 GiB gp3 root disk | $0.08/GiB-month | $1.60 |
| **Baseline** | **about $0.12/hour** | **$88.62–$90.00/month** |

At these observed rates, two hours of provisioned runtime is approximately $0.24–$0.25 before extras. Include provisioning and deletion time in your session budget. Spot prices and availability change, and replacements may temporarily add capacity. CloudWatch ingestion/storage, ECR storage/scanning, data transfer, and any later load balancer are additional. There is no new VPC or NAT gateway charge in this plan. Cluster charges continue even without application traffic.

Worker rates were read through the EC2 Spot price-history API for Linux/UNIX in `us-east-1a` and `us-east-1b`. References: [Spot managed node groups](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html), [EKS pricing](https://aws.amazon.com/eks/pricing/), [public IPv4 pricing](https://aws.amazon.com/vpc/pricing/), [gp3 pricing](https://aws.amazon.com/ebs/general-purpose/). These are estimates, not a billing guarantee or an automatic spending limit.

## Future Cleanup

The manual workflow plans by default and applies when deployment is selected. Resources remain running after success or failure. There is no Start/Stop workflow or automatic destruction. When removal is explicitly requested, destroy the Kubernetes application unit before EKS through reviewed Terragrunt plans.

Remove application ingresses/services and their controller-created load balancers while the cluster is still available. Then review a destroy plan for the EKS unit only. Terraform tracks the project cluster, node group, IAM roles, add-ons, launch template, and log group; EKS manages the corresponding worker instances, instance profile, and cluster security group. Root disks are set to delete on termination. Future persistent volumes or other retained data need a separate decision.

The default VPC, default subnets, routes, ECR repository, existing Lambda/API, and other stacks are outside this EKS unit and must remain. Keep the Terraform backend until all dependent project stacks have been cleaned up. No cleanup or deletion is performed during this planning step.

## Validation

Terraform validation and all three mocked EKS tests passed on October 25, 2026. Tests check restricted API access, explicit operator authorization, worker hardening and capacity, CNI role isolation, scoped image pulls, finite logs, and rejection of an open API or unsupported zone. Additional mocked application tests and deployment safety tests cover the private workload, plan-only behavior, and rejection of destructive deployment plans. Workflow syntax and Terraform/Terragrunt formatting passed locally. The replacement workflow requires a merged-main live run before claiming successful worker and application deployment.

The reviewed live EKS plan proposes **19 additions, zero changes, and zero deletions**:

| Resource | Count |
|---|---:|
| EKS cluster | 1 |
| Managed worker group | 1 |
| Hardened launch template | 1 |
| Core add-ons (VPC CNI, kube-proxy, CoreDNS) | 3 |
| Service IAM roles (control plane, nodes, CNI) | 3 |
| Managed service-policy attachments | 3 |
| Scoped image-pull inline policy | 1 |
| Cluster OIDC provider for the CNI service account | 1 |
| Operator and deployment-workflow access entries and policy associations | 4 |
| Control-plane log group | 1 |

The plan resolves CoreDNS `v1.14.7-eksbuild.22`, kube-proxy `v1.36.0-eksbuild.58`, and VPC CNI `v1.23.2-eksbuild.8`. It contains no managed VPC, subnet, route, gateway, or shared subnet-tag resources. EKS-created worker instances and the cluster security group are service-managed children rather than additional Terraform resource entries.

The private reviewed EKS plan is saved locally at `infrastructure/state/dev-eks.tfplan`; operator access settings remain in ignored `eks.local.hcl`. EKS applies were attempted; the interrupted run created the control plane but no worker group. Its partially persisted state has been recovered using exact ownership-checked Terraform imports; a fresh plan is required before resuming. Separately, the reviewed three-resource IAM-only bootstrap was applied through Terragrunt and followed by a no-change plan. Regenerate and review the EKS plan if configuration, operator IP, version compatibility, shared networking, or pricing changes before deployment.
