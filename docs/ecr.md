# Risk-Service Image Registry

The private ECR repository is named `clinical-trial-site-risk-monitor-dev-risk-service`: project, environment, then the service it stores. Terraform defines the repository in `infrastructure/modules/ecr`; Terragrunt supplies development settings in `infrastructure/live/dev/ecr`.

## Configuration

- Immutable tags prevent overwriting an existing version. The publishing workflow uses the full commit SHA rather than reusing `latest`.
- AES-256 encryption protects stored images.
- Basic scan-on-push checks uploaded images for vulnerabilities. Scan results must be reviewed; enabling scanning alone does not block a deployment.
- No public or cross-account repository policy is granted. The GitHub role has a separate scoped publishing policy. EKS pull permissions will be added with the cluster infrastructure.
- Forced deletion is disabled, so Terraform cannot delete a populated repository without first addressing its images.
- Project, environment, management, and name tags identify the resource.

The ECR stack creates image storage only. The operator-managed GitHub access stack separately grants publishing permissions. Registry scanning settings are not changed account-wide.

## Deploy Through Terragrunt

Use operator AWS credentials and the existing ignored `deployment.local.hcl` settings described in [setup](setup.md). The Lambda CI role does not manage this stack. State is encrypted in the existing S3 backend under `dev/ecr/terraform.tfstate`, with native S3 locking.

From the repository root:

```powershell
terragrunt --working-dir infrastructure/live/dev/ecr init -input=false
terragrunt --working-dir infrastructure/live/dev/ecr validate
terragrunt --working-dir infrastructure/live/dev/ecr test
terragrunt --working-dir infrastructure/live/dev/ecr plan -out=ecr.tfplan
terragrunt --working-dir infrastructure/live/dev/ecr apply ecr.tfplan
```

Review the plan before applying. Expect one private repository to be added. Keep saved plans, state, repository URLs, and ARNs out of Git and public logs. Terraform marks the account-bearing outputs sensitive; `output -raw` explicitly reveals them, so use it only when needed privately.

## Validation Status

Deployed and verified on October 25, 2026. Terraform validation and both mocked tests passed. The reviewed live plan added exactly one repository, and the saved plan was applied through Terragrunt. AWS read-back confirmed the repository name, immutable tags, encryption, scan-on-push, and all project tags. A post-deployment plan reported no changes. The private saved plan was removed afterward.

The GitHub Actions module-check loop includes ECR and has passed on GitHub, alongside container and application tests.

## Publish Through GitHub Actions

The `publish-image` job in [lambda.yml](../.github/workflows/lambda.yml) runs only for an explicit manual workflow run on `main`, after both CI checks and container tests pass. Pull requests and ordinary pushes do not publish images.

After these changes are merged:

1. Open **Actions → Lambda CI and dev deployment → Run workflow**.
2. Select `main`, enable `publish_image`, and leave `deploy` unchecked to avoid applying Lambda changes.
3. Wait for `publish-image` to succeed. The separate `dev` job still generates its normal Lambda plan.
4. Check the private ECR repository's Images tab for the full workflow commit SHA and review its scan results.

The job rebuilds and tests the exact image it will push before obtaining temporary AWS credentials through OIDC. It verifies the commit tag and digest in ECR after the push. Rerunning a commit that is already published preserves that existing immutable image; it does not overwrite it with a rebuilt image. Permission failures and failed pushes fail the job. Temporary Docker registry credentials are removed in an `always()` cleanup step.

Policy `publish-dev-risk-service-image`, managed by Terraform in `infrastructure/modules/github-actions/ecr.tf`, grants upload and image inspection actions only on this repository. `ecr:GetAuthorizationToken` requires `Resource: "*"`; it is limited to the development region. The policy grants neither image deletion nor repository creation, configuration, or deletion. It does not give CI access to the ECR stack's state. See [AWS's publishing permissions](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-push-iam.html).

The workflow uses the existing encrypted `PROJECT_AWS_ACCOUNT_ID` secret. Registry URLs and account IDs are constructed privately and masked; registry passwords are piped to Docker through standard input. No new AWS access keys or GitHub secrets are needed.

**Publishing validation:** workflow syntax, mocked IAM security tests, and local shell checks for first publish, existing tag, denied access, failed push, and credential cleanup have passed. The reviewed Terraform plan added only `publish-dev-risk-service-image`; it was applied through Terragrunt, verified by AWS read-back, and followed by a no-change plan on October 25, 2026. The private saved plan was removed.

The first [publishing run](https://github.com/rohitjain2021/clinical-trial-site-risk-monitor/actions/runs/40248817341) succeeded on October 25, 2026 for main commit `817b71ca41138e6ffe07d68aeffe67ee6705c817`, with `publish_image=true` and `deploy=false`. All CI checks passed, the publishing job verified the tag and digest, and temporary credential cleanup succeeded. Independent AWS read-back confirmed the commit-tagged image exists. Lambda apply was skipped. This verifies publication, not vulnerability clearance or an EKS deployment; review ECR scan findings before deploying the image.

References: [ECR image tag immutability](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-tag-mutability.html), [basic image scanning](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-scanning-basic.html).
