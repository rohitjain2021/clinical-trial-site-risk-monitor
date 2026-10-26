# Development EKS Cluster

Defines a project-named EKS cluster, one Spot `t3.medium` worker for short development sessions, explicit operator access, core add-ons, service IAM roles, hardened node launch template, and finite control-plane logging. Reads the shared default VPC and two default subnets using data sources; creates no VPC, subnet, gateway, route, or shared subnet tag. Spot is interruptible and not free; destroy the EKS unit between sessions to stop its ongoing cluster/worker charges. No automatic expiry is configured.

Use the development Terragrunt unit in `infrastructure/live/dev/eks`. Operator access settings stay in ignored `eks.local.hcl`; an example is provided. See the [EKS planning guide](../../../docs/eks.md) for inputs, costs, validation, network assumptions, and future cleanup. This change prepares a plan and does not apply it.

The separate [demo flow](../../../docs/demo.md) applies/destroys this unit only on an explicit manual operation. Its IAM bootstrap supplies mandatory service-role boundaries and a separate workflow access entry. The application is managed by `infrastructure/modules/demo-app`, which must be destroyed before EKS.
