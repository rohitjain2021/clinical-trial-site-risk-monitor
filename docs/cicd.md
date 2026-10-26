# GitHub Actions CI/CD

The workflow is defined in [lambda.yml](../.github/workflows/lambda.yml). GitHub Actions authenticates to AWS using OIDC, then runs Terragrunt and Terraform against the development Lambda's shared S3 state. No AWS access-key secrets are needed.

Deployment identifiers come from encrypted Actions secrets and an ignored local HCL file. CI masks them before planning and scans Git history with Gitleaks. See the [security guide](security.md) for the required secrets and existing-history limitations.

## Workflow Behavior

| Trigger | Checks | AWS actions |
|---|---|---|
| Pull request | Python response and risk-service tests, container build and HTTP checks, formatting, Terraform validation, mocked security tests | None; no OIDC permission |
| Push to `main` | Same checks | Authenticate and generate a Lambda plan |
| Manual run on `main`, `deploy` unchecked | Same checks | Generate a Lambda plan |
| Manual run on `main`, `deploy` checked | Same checks | Plan, apply, invoke Lambda, verify signed API requests and unsigned denial |
| Manual run on `main`, `publish_image` checked | Same checks, then rebuild and test the image to publish | Publish a commit-tagged image to private ECR; Lambda apply still requires `deploy` |

The plan appears in masked run logs; raw plan output is not copied to the job summary. Pushes never apply infrastructure changes. To deploy, first review a main-branch plan, then open **Actions → Lambda CI and dev deployment → Run workflow**, select `main`, and check `deploy`. This is an explicit deployment approval by a repository maintainer, not a GitHub Environment required-reviewer gate. The manual run creates a fresh plan for the selected commit and applies that plan in the same job; it does not reuse an earlier run's plan. Add a protected environment and matching OIDC trust through infrastructure as code if separate reviewer approval is later required.

The AWS job is limited to `main`, uses a repository-specific concurrency group, and does not cancel a running deployment. S3 locking also serializes Terraform state operations. Terraform manages Lambda deployment; the AWS CLI invocation afterward is a functional check, not infrastructure creation.

The separate `container` job builds the FastAPI Docker image and runs [scripts/check_container.py](../scripts/check_container.py). It checks real HTTP responses and the restricted runtime, then removes its temporary container. It needs no AWS credentials and does not publish an image. The `dev` job requires both `checks` and `container` to pass. See the [container guide](container.md) for local commands and expected responses.

The `publish-image` job also requires both checks, runs only on manual `main` runs with `publish_image` enabled, and obtains OIDC credentials after its own image build and HTTP checks. It publishes the full commit SHA as an immutable ECR tag, verifies that ECR returns the tag and digest, and removes temporary Docker credentials even after failure. An existing commit tag is retained on reruns. This publishes an image without deploying a running service. See the [ECR guide](ecr.md) for activation and verification steps.

Application Python is pinned to 3.13 in CI setup and the container image to match Lambda. The container smoke-test host uses the runner's `python3` with only standard-library modules. Terraform is 1.16.6 and Terragrunt is 1.1.6. All jobs use `ubuntu-24.04` to avoid automatic runner OS migrations. Third-party actions are pinned to commit SHAs, with checkout, Python setup, and Terraform setup using Node 24 runtimes. Terragrunt's Linux download is verified against the release checksum file. The shared setup steps are in [.github/actions/setup-tools/action.yml](../.github/actions/setup-tools/action.yml).

## AWS Trust and Permissions

The separate [demo workflow](../.github/workflows/demo.yml) provides manual Start/Stop on `main` using its own Terraform-managed OIDC role. It deploys and verifies private FastAPI through the EKS and Kubernetes application units, or destroys those two units in order. The existing Lambda deployment role retains its original scope. See the [demo guide](demo.md) for one-time setup, costs, guarded cleanup, and current validation limits.

The [GitHub access Terraform module](../infrastructure/modules/github-actions/main.tf), deployed through `infrastructure/live/dev/github-actions`, creates:

- GitHub's OIDC provider with audience `sts.amazonaws.com`.
- Role `clinical-trial-site-risk-monitor-dev-github-deploy`, trusted only for this repository's `main` branch. Exact legacy and immutable-ID subject formats are accepted; forks, pull-request subjects, feature branches, and environment subjects are not.
- An inline deployment policy scoped to the development Lambda, its execution role, log group, state key, and lock key.
- Inline policy `publish-dev-risk-service-image`, permitting image uploads and inspection on the private risk-service ECR repository, plus regional ECR authentication. It grants no repository administration or image deletion.
- A separate Lambda execution-role permissions boundary that permits only stream creation and event writes in the function's own log group.

The deployment role cannot edit its own trust or permissions, change the boundary policy, remove the Lambda boundary, manage the state bucket, or access the GitHub-access stack's state object. Creating or setting the execution role boundary requires the exact pre-provisioned boundary ARN. Passing that role is allowed only to the Lambda service. `logs:DescribeLogGroups` requires a resource wildcard and is restricted to `us-east-1`; the remaining resource permissions are scoped to the project's resources. `s3:ListBucket` permits listing this state bucket; state object reads/writes are limited to Lambda's key and lock.

The boundary is a cap, not a permission grant: the execution role also needs its inline logging policy. Future application permissions must be reviewed and added to both policies through Terraform when needed.

Operator credentials manage the GitHub access stack separately. Its state is in the project's S3 bucket at `dev/github-actions/terraform.tfstate`. The CI deployment role manages only `dev/lambda/terraform.tfstate` and its `.tflock` object.

## Operator Commands

From the repository root:

```powershell
terragrunt --working-dir infrastructure/live/dev/github-actions init -input=false
terragrunt --working-dir infrastructure/live/dev/github-actions validate
terragrunt --working-dir infrastructure/live/dev/github-actions test
terragrunt --working-dir infrastructure/live/dev/github-actions plan "-out=github-access.tfplan"
terragrunt --working-dir infrastructure/live/dev/github-actions apply github-access.tfplan
```

This initial stack adds four resources. After deployment a plan should report no changes. It must exist before the main-branch AWS job can authenticate and before CI can create the bounded Lambda role. The account had no OIDC provider when this stack was introduced; in another account with an existing GitHub provider, import or reference that provider rather than create a duplicate.

## Validation and Activation

Local validation includes mocked IAM/security tests, Terraform validation, a no-change plan for the deployed access stack, and `actionlint` validation of the workflow. The Lambda unit now includes the minimal API Gateway infrastructure; see the [API guide](api.md) for its routes and operator bootstrap order.

GitHub-to-AWS authentication and the initial Lambda deployment have passed in GitHub Actions. New API smoke tests run after the API change is merged and the next manual deployment is triggered. The operator-managed API permissions restrict CI to the exact API ID; the GitHub access stack reads that ID from the Lambda unit's remote state. If AWS reports a missing permission, add only the required scoped permission to Terraform and redeploy the access stack as an operator.

References: [GitHub OIDC with AWS](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws), [AWS Lambda authorization](https://docs.aws.amazon.com/service-authorization/latest/reference/list_lambda.html), and [Terraform S3 backend permissions](https://developer.hashicorp.com/terraform/language/backend/s3).
