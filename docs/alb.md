# Private Application Load Balancer

## Request Path

The internal ALB forwards HTTP requests to the EKS worker on NodePort `30800`. Kubernetes routes that port to the existing FastAPI pods on `8000`. The Service retains its cluster-internal address for existing callers.

Terraform attaches the target group to the EKS-managed Auto Scaling group. Auto Scaling registers replacement workers automatically. This avoids recording ephemeral instance or pod IPs. The attachment owns no worker instances or Auto Scaling group configuration. The design uses instance targets and NodePort, as described in [AWS's EKS traffic modes](https://docs.aws.amazon.com/eks/latest/userguide/alb-ingress.html), with [Auto Scaling target registration](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-target-groups.html#registered-targets).

This single-worker development configuration does not require installing an ingress controller. Terraform owns the ALB, listener, target group, security groups/rules, attachment, and verification job.

## Names and Access

- ALB: `clinical-trial-risk-dev-alb`.
- Target group: `clinical-trial-risk-dev-tg`.
- Dedicated security groups: `clinical-trial-site-risk-monitor-dev-alb` and `clinical-trial-site-risk-monitor-dev-alb-client`.
- Verification job: `risk-alb-verification` in the existing application namespace.

Shorter ALB/target-group names respect AWS's name-length limit. Tags retain the full project name, environment, and Terraform ownership.

The ALB is internal and reuses the two existing EKS subnets. It accepts port `80` from the EKS security group for in-cluster checks and from the dedicated client group reserved for Lambda. Its egress is restricted to worker port `30800`; the added worker ingress rule accepts that port from the ALB group. The client group permits only outbound HTTP to the ALB. No internet CIDR rules, new VPC, subnet, route, or NAT gateway are created. Existing EKS-managed self-access rules remain intact.

The listener currently uses private HTTP, without an ALB TLS certificate. This step does not provide end-to-end TLS or attach Lambda to the VPC. Use synthetic prototype data. Lambda-to-ALB integration and any internal TLS requirements are separate implementation work.

## Terraform and Deployment

The module is `infrastructure/modules/alb`, with development configuration in `infrastructure/live/dev/alb` and S3 state key `dev/alb/terraform.tfstate`. Its dependencies are the EKS and application units. Network identifiers, target-group ARN, ALB URL, and client security-group output remain private.

The existing EKS workflow deploys EKS and the application. This step adds ALB validation to pull-request CI; ALB provisioning itself is a separate operator-run Terragrunt unit. The GitHub role has not received load-balancer or Auto Scaling mutation permissions. Automated ALB deployment can be added when extending CI/CD for the remaining components.

After EKS and the application export their updated outputs, run from the repository root using operator credentials and the configured `/32` access:

```powershell
New-Item -ItemType Directory -Force infrastructure/state | Out-Null
terragrunt --working-dir infrastructure/live/dev/alb init -input=false
$albPlan = Join-Path (Get-Location) 'infrastructure/state/alb.tfplan'
terragrunt --working-dir infrastructure/live/dev/alb plan "-out=$albPlan"
# Review the exact resource list, private access rules, and costs before applying.
terragrunt --working-dir infrastructure/live/dev/alb apply $albPlan
```

The initial reviewed plan contains 12 creations: ALB, listener, target group, two security groups, five scoped rules, worker attachment, and verification job. It contains no shared network ownership or instance/pod IP attachments.

## Verification

The target group checks `GET /health` on the traffic port and requires HTTP `200`. A hardened in-cluster job calls the actual ALB DNS endpoint, using the same verifier as the direct Service check. It tests health, the synthetic High-risk assessment with five reasons, `Cache-Control: no-store`, and HTTP `400` for invalid input. Verification pods have distinct labels so they are never application Service targets.

Local tests cover transient readiness, persistent failure, incorrect results, invalid-input rejection, private subnet reuse, exact security-group/port access, worker registration, and rejection of unrelated worker groups or ports. Live verification passed after the reviewed Terraform apply: the ALB is active and internal, one worker target is healthy, the dedicated access groups have no IPv4/IPv6 CIDR rules, and the HTTP verification job succeeded.

## Cost and Explicit Teardown

The ALB adds its own running and usage charges to the EKS estimate; see [AWS load-balancer pricing](https://aws.amazon.com/elasticloadbalancing/pricing/). It remains provisioned until explicit teardown. No idle timer or automatic shutdown is configured.

When asked to remove the backend, use reviewed saved destroy plans in this order:

1. `infrastructure/live/dev/alb`: removes its test job, worker attachment, ALB, target group, listener, and project access groups/rules.
2. `infrastructure/live/dev/demo-app`: removes the application while Kubernetes is still available.
3. `infrastructure/live/dev/eks`: removes workers and the control plane.

Do not destroy all environment units: ECR, Lambda/API, shared networking, IAM bootstrap, and the Terraform backend are retained unless explicitly requested otherwise. Verify absence of the ALB, its project security groups, workers, root disks, and cluster after teardown. Destroying EKS alone would leave the ALB charge and could leave security-group dependencies.
