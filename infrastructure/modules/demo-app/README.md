# Private FastAPI Workload

Terraform manages a dedicated namespace, one hardened FastAPI Deployment, a ClusterIP Service, and an HTTP-verification Job. The image must be pinned to a digest in the project's ECR repository. Each deployment uses a new workflow run ID to force a fresh Job; no public load balancer or persistent storage is created.

The Kubernetes provider uses the cluster endpoint/CA and a short-lived token from the AWS CLI. Deploy through `infrastructure/live/dev/demo-app` after the EKS unit is ready. Destroy this application unit before destroying EKS. See the [deployment guide](../../../docs/deployment.md) for operator settings, costs, and validation status.

The verification pod uses different labels from the application so the Service never routes requests to its test client. Its health check retries transient connection failures before running the assessment and invalid-input checks.
