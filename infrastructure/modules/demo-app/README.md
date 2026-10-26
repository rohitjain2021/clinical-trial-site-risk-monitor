# Private FastAPI Demo Workload

Terraform manages a dedicated namespace, one hardened FastAPI Deployment, a ClusterIP Service, and an HTTP-verification Job. The image must be pinned to a digest in the project's ECR repository. Each Start uses a new workflow run ID to force a fresh Job; no public load balancer or persistent storage is created.

The Kubernetes provider uses the cluster endpoint/CA and a short-lived token from the AWS CLI. Deploy through `infrastructure/live/dev/demo-app` after the EKS unit is ready. Destroy this application unit before destroying EKS. See the [demo guide](../../../docs/demo.md) for operator settings, costs, and validation status.
