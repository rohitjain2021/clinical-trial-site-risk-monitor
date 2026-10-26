# Private Risk-Service Image Repository

Creates one private ECR repository with immutable tags, AES-256 encryption, scan-on-push, project tags, and forced deletion disabled. It does not create public access policies, IAM roles, or account-wide registry settings.

Inputs are `repository_name` and `tags`. Outputs are the name, sensitive ARN, and sensitive repository URL. Deploy through `infrastructure/live/dev/ecr`; its state uses the existing encrypted S3 backend and native locking.

See the [ECR guide](../../../docs/ecr.md) for operator commands and deployment status. GitHub Actions runs module validation and mocked security tests; its existing Lambda deployment role does not manage ECR.
