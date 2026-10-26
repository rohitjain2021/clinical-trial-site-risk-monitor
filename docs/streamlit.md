# Streamlit Interface

The dark-blue-and-orange clinical dashboard supports two ways to review one site:

- **Paste a report:** copy meaningful labelled lines, with no JSON syntax.
- **Fill in fields:** enter site details and numeric counts in a form.

Choose a synthetic example, click **Assess site**, and review enrollment, schedule delay, unresolved issues, the risk rating, numbered reasons, and an optional AI explanation. The empty results panel shows placeholders until a submission succeeds. Changing examples or input methods clears the visible assessment; no extra model call is made until you submit.

## Copy-Paste Example

Copy the following report into **Site report**, or use [the sample text file](examples/site-report.txt):

```text
Site ID: SITE-001
Site name: Northbridge Research Center
Enrollment target: 60
Patients enrolled: 21
Days behind schedule: 18
Patient dropouts: 2
Protocol deviations: 1
Unresolved issues: 3
```

Keep one `Field: value` per line and use the sample's field names. Names may contain spaces and punctuation. Counts and days must be nonnegative whole numbers; the enrollment target must be positive. The app rejects missing, duplicate, or unrecognized fields and does not guess values from arbitrary prose. It converts the report to the existing API format internally; field validation and risk scoring stay in the backend.

The examples are **Delayed enrollment** (High), **Some operational concerns** (Medium), and **Meeting operational targets** (Low). Their ratings are returned by the backend, not assigned by the UI. Use synthetic data only.

## Visual Design

The selected design uses dark blue headers and headings, orange actions and highlights, white panels on a light gray background, green Low-risk indicators, colored risk badges, metric cards, an enrollment progress bar, and a separate AI explanation panel. There is no sidebar: site input and assessment results fill the main workspace, with optional connection details below. The AI explanation box follows the calculated rating: red for High, yellow for Medium, and green for Low. These are status colors; the page theme uses dark blue and orange. Layout and interactive controls remain native Streamlit. Theme settings are in `.streamlit/config.toml`; local styling is in `services/streamlit_ui/style.css`. CSS introduces no extra packages or remote assets. All site names and reason text are escaped before custom HTML rendering; model output is displayed as plain text.

These are frontend changes only. The API contract, server-side SigV4 signing, secret handling, deterministic rules, and model-failure fallback stay in place. No new AWS infrastructure is provisioned.

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

The page should say **Backend: AWS API**. Click **Assess site** with the sample and expect **High** with five reasons. Use the Medium/Low examples in the [risk rules](risk-rules.md) to check other results. Malformed reports, invalid fields, denied access, and unavailable backends show readable errors without private endpoint or credential details.

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

Tests use synthetic credentials and check actual SigV4 signing, temporary session tokens, local mode, request-size limits, endpoint validation, safe errors, report parsing, manual form submission, example switching, and AI success/fallback. The three synthetic examples are also checked against the existing calculator. CI also runs the mocked Terraform policy test. Hosted verification requires merged code and the private Secrets setup above; local client tests alone do not establish that Community Cloud has been configured.

Live operator verification passed with the Terraform-created UI identity: High/Medium/Low assessments and the actual Streamlit form returned the expected results through AWS; the sample form showed five reasons. A signed health request using the UI key returned `403`, and IAM simulation denied S3 discovery, EKS deletion, and IAM creation. Access Analyzer reported zero policy findings. Hosted Secrets setup and hosted-form verification have also been completed; the operator confirmed the sample result and subsequent AI explanation in Community Cloud.

## Optional AI Summary

After the [Bedrock rollout](bedrock.md), successful assessments also show **AI explanation** below the original reasons. If the model is unavailable, the score and reasons still display. The UI key and Secrets configuration require no additional permissions. Hosted High/five-reason scoring and the AI explanation have been verified after the new backend image rollout. The UI HTTP timeout is 25 seconds to allow the optional summary.

## Dashboard Update Status

The redesigned report form passed live AWS tests for all three synthetic scenarios: High, Medium, and Low each returned the expected rating and an available AI explanation. Eight offline UI/client tests passed. Browser visual inspection could not be completed because computer use could not verify the current Chrome URL; use the local preview to review appearance. The dashboard changes are prepared locally and have not been published to the hosted app yet.

After committing, pushing, and merging the frontend changes into the branch tracked by Community Cloud, let Streamlit rebuild or reboot the app. No Lambda or EKS redeployment and no Secrets changes are needed for this dashboard update.
