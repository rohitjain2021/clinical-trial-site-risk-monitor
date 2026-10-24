# Repository Security and Private Deployment Configuration

## What Stays Out of Git

Never commit AWS credentials, session tokens, passwords, private keys, patient data, real trial uploads, Terraform state, or saved plans. Ignore rules exclude common credential files, `.env` files, private deployment settings, state, caches, and private upload directories. These rules do not remove already committed content.

AWS account IDs, bucket names, ARNs, and API URLs are identifiers, not credentials. We still keep the deployed account, state bucket name, and API ID out of current public source and docs. Examples use placeholders or fictitious account `123456789012`. IAM and authentication must protect resources even when their identifiers are known.

## Local Configuration

For a new checkout, copy the example and enter your deployment identifiers:

```powershell
Copy-Item infrastructure/live/dev/deployment.example.hcl infrastructure/live/dev/deployment.local.hcl
```

Do not overwrite an existing `deployment.local.hcl`. The current machine's settings were preserved during this change. This ignored file holds account, bucket, and GitHub identity metadata, not AWS access keys. Authentication stays in the AWS credential chain.

Terragrunt reads this file and supplies Terraform inputs. The account guard, resource names, state backend, and exact OIDC subjects retain their effective values. Bootstrap reads the same private file. Mocked Terraform tests use fictitious inputs and need no private configuration.

## GitHub Actions Secrets

The repository has these encrypted Actions secrets:

| Name | Purpose |
|---|---|
| `PROJECT_AWS_ACCOUNT_ID` | Target account, deployment role ARN, account guard, and masking |
| `PROJECT_TF_STATE_BUCKET` | Existing state bucket name for generated Terragrunt configuration |
| `PROJECT_API_GATEWAY_ID` | Existing API ID to mask in plan output and endpoint URLs |

These are metadata stored as secrets for disclosure control, not AWS credentials. OIDC still provides temporary deployment credentials. The runner recreates the ignored HCL file, masks the identifiers before AWS/Terraform commands run, and does not publish raw plan files or state as artifacts. Pull-request checks do not receive these values or AWS access.

For another repository/environment, configure these three secrets before merging or running deployment. Preserve actual resource names: parameterizing identifiers must not accidentally create another backend or deployment.

## Secret Scanning

GitHub secret scanning and push protection are enabled. CI downloads checksum-verified Gitleaks `8.30.1` and scans available Git history with redacted findings. A finding fails checks; do not bypass a real credential alert.

The history scan found no credential leaks at the time of this change. Scanning is not a guarantee that every possible secret will be detected. Review staged configuration, data, and generated files before committing.

## Existing Public History

Earlier commits, pull requests, and Actions logs can still contain deployment identifiers. This change removes them from current source and masks configured future workflow output; it does not rewrite history or delete earlier logs. Public copies can remain after deletion.

No credential requiring rotation was found. If a real secret is exposed, revoke/rotate it immediately, then address history and other copies. Removing the latest file does not invalidate the credential.

References: [AWS account identifiers](https://docs.aws.amazon.com/accounts/latest/reference/manage-acct-identifiers.html), [GitHub secret scanning](https://docs.github.com/en/code-security/concepts/secret-security/secret-scanning), and [push protection](https://docs.github.com/en/code-security/concepts/secret-security/push-protection).
