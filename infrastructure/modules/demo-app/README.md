# Private FastAPI Workload

Terraform manages a dedicated namespace, one hardened FastAPI Deployment, a NodePort Service with its existing cluster-internal address, and an HTTP-verification Job. The image must be pinned to a digest in the project's ECR repository. Each deployment uses a new workflow run ID to force a fresh Job; no public load balancer or persistent storage is created.

The Kubernetes provider uses the cluster endpoint/CA and a short-lived token from the AWS CLI. Deploy through `infrastructure/live/dev/demo-app` after the EKS unit is ready. Destroy this application unit before destroying EKS. See the [deployment guide](../../../docs/deployment.md) for operator settings, costs, and validation status.

The verification pod uses different labels from the application so the Service never routes requests to its test client. Its health check retries transient connection failures before running the assessment and invalid-input checks.

The private ALB reaches worker port `30800`, which forwards to FastAPI port `8000`. Shared `verify.py` checks either this Service or the ALB. ALB infrastructure is owned by the separate [ALB module](../alb/README.md).

## Bedrock-Capable Deployment

The application uses a dedicated service account annotated with the EKS risk-service IRSA role, enables optional Nova Micro explanations, and disables instance-metadata credential discovery. Kubernetes API token automount remains disabled. No static AWS keys are mounted. Health remains independent of Bedrock. The in-cluster verification job requires a real available explanation to verify this rollout; a legacy image fails that gate. Normal assessment requests still return rule-based scores during model outages. See the [Bedrock guide](../../../docs/bedrock.md).
