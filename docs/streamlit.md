# Streamlit Interface

Paste one synthetic site record as JSON, click **Assess site**, and read the risk level and reasons. The existing [sample](examples/site-assessment.json) fills the form and is available in **Copy sample JSON**. The UI keeps risk rules in FastAPI and stores no submissions.

## Hosted API Connection

The entry file is `services/streamlit_ui/app.py`, with dependencies in the adjacent `requirements.txt`. Community Cloud should track the merged `main` branch. The Streamlit server signs requests with AWS SigV4 and sends them over HTTPS to API Gateway. Requests then follow Lambda -> private ALB -> FastAPI on EKS. The browser never receives the AWS key or secret. CORS is unnecessary because the request runs on the Streamlit server.

### 1. Provision Scoped AWS Access

The operator-managed Terraform unit `infrastructure/live/dev/streamlit-access` creates a dedicated project-named IAM user, a permissions boundary, an inline policy, and an access key. Both policies allow only `execute-api:Invoke` on this API's `dev/POST/site-assessments` route. There is no console login, health-route access, AWS resource management, or reuse of operator/CI credentials. The existing API retains IAM authentication.

Community Cloud stores server secrets but does not supply an AWS instance role. This implementation uses a dedicated access key for that hosting choice. The key persists until explicitly rotated or revoked; keep it only in encrypted Terraform state and Streamlit Secrets. On AWS hosting, the client also supports the SDK credential chain so a scoped workload role can replace a stored key.

From the repository root, initialize, review a saved plan, then apply that exact plan:

```powershell
terragrunt --non-interactive --working-dir infrastructure/live/dev/streamlit-access init
terragrunt --non-interactive --working-dir infrastructure/live/dev/streamlit-access plan -out="$PWD/infrastructure/state/streamlit-access.tfplan"
terragrunt --non-interactive --working-dir infrastructure/live/dev/streamlit-access apply "$PWD/infrastructure/state/streamlit-access.tfplan"
python scripts/export_streamlit_secrets.py
```

The shared encrypted S3 backend stores this unit separately at `dev/streamlit-access/terraform.tfstate`. Existing local deployment settings and the Lambda unit's outputs must be available. Do not run sensitive Terraform output commands in shared terminals or CI logs. The export script captures outputs and writes only ignored `.streamlit/secrets.toml`; it prints no values. Never commit that file or paste its contents into chat.

### 2. Save Settings in Community Cloud

After merging the UI changes, open your app's **Manage app -> Settings -> Secrets**, paste the complete local `.streamlit/secrets.toml` contents there, and save. See [Streamlit's Secrets instructions](https://docs.streamlit.io/deploy/streamlit-community-cloud/deploy-your-app/secrets-management). Restart/reboot the app if needed after saving.

The private file has this structure (placeholders below are not usable credentials):

```toml
[risk_api]
base_url = "https://<api-id>.execute-api.us-east-1.amazonaws.com/dev"

[aws]
access_key_id = "<dedicated-ui-access-key>"
secret_access_key = "<dedicated-ui-secret>"
# session_token = "<token>" # Only for temporary credentials; omit for this IAM key.
```

The page should say **Backend: AWS API**. Click **Assess site** with the sample and expect **High** with five reasons. Use the Medium/Low examples in the [risk rules](risk-rules.md) to check other results. Malformed JSON, invalid fields, denied access, and unavailable backends show generic readable errors without private endpoint or credential details.

This authenticates the Streamlit server to AWS; it does not add individual user authentication to the page. Anyone allowed to use the hosted app can submit assessments through its scoped identity. Keep the demo synthetic; use Community Cloud sharing controls when access needs to be restricted.

### Credentials and Teardown

Rotate or revoke the dedicated UI key through this Terraform unit, then replace/delete the hosted Secrets configuration. Do not create keys manually in the AWS console. To rotate, review a saved plan with `-replace=aws_iam_access_key.ui`, apply it, rerun the export script, and promptly save the new settings in Streamlit; requests using the previous key will fail. Terraform state versions can retain old sensitive values, so keep the backend encrypted and access restricted.

Backend teardown remains explicit and uses the [Lambda disconnect procedure](lambda-backend.md#explicit-disconnect-before-teardown). This UI does not provision or destroy EKS. If EKS is unavailable, assessments fail safely; they do not silently run scoring in the browser. Deleting the Streamlit access unit revokes its AWS key without deleting EKS, ALB, Lambda, or API Gateway.

## Run Locally

```powershell
python -m venv services/streamlit_ui/.venv
services/streamlit_ui/.venv/Scripts/python.exe -m pip install -r services/streamlit_ui/requirements.txt
services/streamlit_ui/.venv/Scripts/python.exe -m streamlit run services/streamlit_ui/app.py --server.address 127.0.0.1 --server.port 8501 --server.headless true --browser.gatherUsageStats false
```

With the ignored secrets file present, this local UI calls the signed AWS API. Without `risk_api.base_url`, it retains local demo mode and calls `http://127.0.0.1:8000/site-assessments`. Start local FastAPI separately using the [risk-service guide](risk-service.md); the page says **Backend: local FastAPI**. Press Ctrl+C to stop local servers.

## Verification

Run the client/form tests without AWS access:

```powershell
services/streamlit_ui/.venv/Scripts/python.exe -m unittest discover -s services/streamlit_ui -p 'test_*.py' -v
```

Tests use synthetic credentials and check actual SigV4 signing, temporary session tokens, local mode, request-size limits, endpoint validation, safe errors, and real Streamlit form submission and recovery. CI also runs the mocked Terraform policy test. Hosted verification requires merged code and the private Secrets setup above; local client tests alone do not establish that Community Cloud has been configured.

Live operator verification passed with the Terraform-created UI identity: High/Medium/Low assessments and the actual Streamlit form returned the expected results through AWS; the sample form showed five reasons. A signed health request using the UI key returned `403`, and IAM simulation denied S3 discovery, EKS deletion, and IAM creation. Access Analyzer reported zero policy findings. These verify the local UI-to-cloud path; hosted Secrets setup and hosted-form verification remain pending.
