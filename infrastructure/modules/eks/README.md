# Development EKS Cluster

Defines a project-named EKS cluster, one Spot `t3.medium` worker for short development sessions, explicit operator access, core add-ons, service IAM roles, hardened node launch template, and finite control-plane logging. Reads the shared default VPC and two default subnets using data sources; creates no VPC, subnet, gateway, route, or shared subnet tag. Spot is interruptible and not free; destroy the EKS unit between sessions to stop its ongoing cluster/worker charges. No automatic expiry is configured.

Use the development Terragrunt unit in `infrastructure/live/dev/eks`. Operator access settings stay in ignored `eks.local.hcl`; an example is provided. See the [EKS planning guide](../../../docs/eks.md) for inputs, costs, validation, network assumptions, and future cleanup. The cluster is deployed; further changes require reviewed Terraform plans.

The separate [demo flow](../../../docs/demo.md) applies/destroys this unit only on an explicit manual operation. Its IAM bootstrap supplies mandatory service-role boundaries and a separate workflow access entry. The application is managed by `infrastructure/modules/demo-app`, which must be destroyed before EKS.

The risk-service IRSA role reuses the existing cluster OIDC provider and trusts only its exact application namespace/service account. Its boundary and inline policy allow only `bedrock:InvokeModel` on regional Nova Micro. Workers and CNI receive no model permissions. The operator-managed GitHub IAM bootstrap must supply the new `risk` boundary before role creation. See the [Bedrock guide](../../../docs/bedrock.md).
