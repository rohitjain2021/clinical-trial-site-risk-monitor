# Streamlit API Access

Creates `clinical-trial-site-risk-monitor-dev-streamlit`: an IAM user with one access key, an inline invocation policy, and a matching permissions boundary. Both policies permit only `execute-api:Invoke` on the existing API's `dev/POST/site-assessments` route. It has no console login or infrastructure permissions.

The operator-run `infrastructure/live/dev/streamlit-access` unit obtains the API execution ARN from the Lambda unit and uses separate encrypted S3 state. The GitHub deployment role is not granted access to this unit's state or credentials. CI runs mocked policy tests only.

`app_secrets` is sensitive. Terraform still stores the actual key in state; sensitive marking suppresses display rather than removing it from state. Use `python scripts/export_streamlit_secrets.py` to write the ignored local `.streamlit/secrets.toml`, then copy it into the hosted app's Secrets settings. Never commit the file, print outputs in CI, or use operator credentials in Community Cloud.

The key is persistent and must be explicitly rotated/revoked through Terraform. No automatic teardown or extra application authentication is introduced. See the [Streamlit guide](../../../docs/streamlit.md) for deployment, rotation, and verification.
