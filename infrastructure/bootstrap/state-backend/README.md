# Development Terraform State Backend

Bucket: **`clinical-trial-site-risk-monitor-tfstate-dev-<AWS_ACCOUNT_ID>`**, in `us-east-1`, account `<AWS_ACCOUNT_ID>`.

The name identifies the project, Terraform state purpose, development environment, and owning account. It stores infrastructure state and lock objects, not clinical data or application uploads.

Terraform defines six resources: the bucket, versioning, AES256 default encryption, public access blocks, bucket ownership controls, and an HTTPS-only bucket policy. `prevent_destroy` and `force_destroy = false` protect against Terraform accidentally removing the state bucket. Version history has no automatic expiry. These protections do not prevent a separately authorized AWS administrator from changing or deleting resources outside Terraform.

## Bootstrap with Infrastructure as Code

From the repository root, run each command and confirm it succeeds:

```powershell
terragrunt --working-dir infrastructure/bootstrap/state-backend init -input=false
terragrunt --working-dir infrastructure/bootstrap/state-backend validate
terragrunt --working-dir infrastructure/bootstrap/state-backend test
terragrunt --working-dir infrastructure/bootstrap/state-backend plan "-out=state-backend.tfplan"
terragrunt --working-dir infrastructure/bootstrap/state-backend apply state-backend.tfplan
```

The initial plan adds six resources. The test uses a mocked AWS provider and checks the bucket name, encryption, versioning, ownership, public-access blocks, and TLS policy. The apply command creates only the state backend resources.

This bootstrap stack deliberately stores its own state locally at `infrastructure/state/bootstrap/terraform.tfstate`, outside Terragrunt's cache. The bucket must exist before application stacks can use it. Back up bootstrap state securely and retain it with the bootstrap operator; it is Git-ignored and is not the state used by the future Lambda CI pipeline. Do not run a second bootstrap deployment from another machine without first transferring or migrating that state. Move bootstrap state to an independently managed backend if bootstrap management is later shared.

After creation, a fresh bootstrap `plan` should report no changes. To verify bucket settings, use Terraform refresh/plan or read-only AWS commands; resource changes remain in Terraform.

## Application State and Migration

`infrastructure/live/root.hcl` generates an S3 backend for each application unit. Lambda uses:

- State key: `dev/lambda/terraform.tfstate`
- Lock key: `dev/lambda/terraform.tfstate.tflock`
- Encryption: `encrypt = true`
- Locking: `use_lockfile = true` (requires Terraform 1.10 or later)

The bucket is provisioned only by the bootstrap Terraform stack; Terragrunt does not automatically create or manage it through a `remote_state` block.

When changing an already-initialized unit from local to S3, preserve its local state and cache and run:

```powershell
terragrunt --working-dir infrastructure/live/dev/lambda init -migrate-state
terragrunt --working-dir infrastructure/live/dev/lambda plan
```

Answer the state-copy prompt only after verifying the source and destination. Do not substitute `-reconfigure` when existing state needs migration. With no existing local state, initialization simply configures the S3 backend. For a fresh clone after bootstrap, normal `init` connects to existing remote state.

Terraform acquires and releases an S3 lock during planning and applying. This is Terraform concurrency locking, not S3 Object Lock retention; no DynamoDB table is needed. Plans and ZIPs stay local in the ignored cache. A state object is written when Terraform persists actual infrastructure state, so an empty environment can have a successful plan before any state object exists.

## Access for the Future CI Role

The bucket policy only denies insecure transport; it grants no access. The future deployment role will need these state permissions in addition to separately scoped infrastructure deployment permissions:

| Actions | Resource |
|---|---|
| `s3:ListBucket` | This bucket ARN |
| `s3:GetObject`, `s3:PutObject` | This bucket's `dev/lambda/terraform.tfstate` object |
| `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject` | This bucket's `dev/lambda/terraform.tfstate.tflock` object |

The Lambda execution role receives no state bucket access. No GitHub role or OIDC provider is created by this stack. See the [HashiCorp S3 backend documentation](https://developer.hashicorp.com/terraform/language/backend/s3) for backend permissions and locking.
