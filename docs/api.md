# Minimal Site Risk Monitor API

Development base URL: `https://<API_ID>.execute-api.us-east-1.amazonaws.com/dev`

The API, integration, routes, throttling, Lambda invocation grants, and access log group are defined in `infrastructure/modules/lambda/api.tf`. All AWS resources and permissions are managed through Terraform/Terragrunt.

| Method and path | Purpose | Success |
|---|---|---|
| `GET /health` | Verify API-to-Lambda connectivity | `200`, `status: ok` |
| `POST /site-assessments` | Validate one aggregate site record | `200`, `status: validated` |

POST does not store records, create an assessment ID, queue work, or calculate risk. The response explicitly reports validation only. File uploads and batches are not implemented. Streamlit can eventually parse a file and submit records from its Python server.

## Authentication

Both routes use `AWS_IAM`: requests require AWS Signature Version 4 signing for service `execute-api`, region `us-east-1`, plus `execute-api:Invoke` permission for the route. Temporary credentials also need the session token header. Opening the URL in a browser without signing returns `403`.

The deployment role can invoke only this API's two development routes. A future Streamlit runtime needs its own Terraform-managed caller role; do not reuse the deployment role or send AWS credentials to a browser. CORS is not needed for the intended server-side Streamlit calls and is not enabled.

## Submission Contract

Send `Content-Type: application/json` and the fields in the [synthetic example](examples/site-assessment.json): `site_id`, `site_name`, `enrollment_target`, `actual_enrollment`, `days_behind_schedule`, `patient_dropout_count`, `protocol_deviation_count`, and `unresolved_issue_count`.

- ID: 1–64 letters, digits, underscores, or hyphens.
- Name: 1–200 nonblank characters.
- Counts/days: nonnegative integers, not booleans or numeric strings.
- Enrollment target must be positive; dropout count cannot exceed actual enrollment.
- Unknown fields and batches are rejected. Only aggregate site data belongs in this contract; do not include patient data.

Successful response:

```json
{
  "status": "validated",
  "site_id": "SITE-001",
  "message": "Site data is valid. Storage and risk analysis are not implemented yet."
}
```

Errors: `400` for invalid JSON/site data; `413` for decoded bodies over 64 KiB; `415` for unsupported content type. Unknown routes are not exposed. Responses use `Cache-Control: no-store`.

## Infrastructure and Deployment

The `dev` stage uses a 5 requests/second throttle with burst 10. Throttling is best effort and can return `429`; it is not a strict cost ceiling. Lambda invoke grants restrict the source account, API ID, stage, method, and path. Access logs retain only request IDs, route keys, and status codes for 14 days. The application does not log submission bodies.

The operator-managed GitHub access stack provisions a delivery policy restricted to this account and the API log group's streams. First-time API creation is operator-run Terraform so CI permissions can use the exact generated API ID. CI can manage that API afterward, but cannot create arbitrary APIs or recreate a deleted API. API replacement requires operator-run Terraform and a refresh of the CI permissions. CI's CloudWatch log-delivery/discovery permissions require a resource wildcard and are restricted to `us-east-1`; CI cannot edit the account log resource policy.

The GitHub access Terragrunt unit reads `api_gateway_id` from the Lambda unit's S3 state. For a fresh environment, bootstrap the state bucket, OIDC/boundary and log delivery policy first, create the Lambda/API using operator credentials, then enable that dependency and update the CI role. Do not run the complete initial bootstrap as a parallel deployment.

The initial API creation and handler update were applied through Terraform. Future normal updates run through the manual deployment workflow, which now tests signed GET/POST requests and verifies unsigned requests are denied.

## Verification

```powershell
python -m unittest discover -s services/lambda -p 'test_*.py' -v
terragrunt --working-dir infrastructure/live/dev/lambda test
terragrunt --working-dir infrastructure/live/dev/lambda plan
terragrunt --working-dir infrastructure/live/dev/lambda output -raw api_base_url
```

Local Python tests cover valid/invalid data, content types, encoding, size limits, and health checks. Terraform tests mock AWS and check IAM authorization, invoke-grant scope, retention, and throttling. Live operator tests confirmed signed GET/POST return 200, unsigned GET returns 403, and invalid POST returns 400.
