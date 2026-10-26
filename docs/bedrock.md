# Bedrock Risk Explanations

The risk service can use **Amazon Nova Micro** (`amazon.nova-micro-v1:0`) in `us-east-1` to explain the existing prototype result. Python rules still calculate the risk level and reasons. The generated explanation is optional, separate text; it cannot modify the score and is not a clinical judgment.

## Request Flow

Streamlit -> authenticated API Gateway -> Lambda -> internal ALB -> FastAPI -> Bedrock. FastAPI returns the original risk result plus an optional `explanation` object. Streamlit shows it below the rule-based reasons. Site records are not stored, and Snowflake remains a separate task.

`services/risk_service/explanation.py` sends only `risk_level`, `rules_version`, and calculated `reasons`. Site names, site IDs, raw submissions, and credentials are excluded. The prompt asks for 2 or 3 factual sentences with no invented findings, changed scores, medical advice, or recommendations. This limits the task but does not guarantee factual model output; the original reasons remain visible for comparison.

The [Bedrock Converse API](https://docs.aws.amazon.com/nova/latest/userguide/using-converse-api.html) uses a maximum of 180 output tokens and temperature zero. Only a nonempty, complete `end_turn` response up to 2,000 characters is displayed. Truncated, malformed, denied, throttled, and timed-out responses become an unavailable status. There are no automatic inference retries, agents, tools, retrieval, fine-tuning, or reserved throughput. Standard model token charges apply per request.

## Response Contract

The original `site_id`, `risk_level`, `rules_version`, and `reasons` fields are unchanged. When enabled, an additional field is returned:

```json
{
  "explanation": {
    "status": "available",
    "model_id": "amazon.nova-micro-v1:0",
    "text": "A short AI-generated operational summary."
  }
}
```

If the model fails, `status` is `unavailable` and `text` is `null`; the assessment still returns `200` with its calculated score and reasons. Lambda whitelists and bounds this optional object and never allows model output to replace the original fields. The UI displays the summary as plain text, or a readable unavailable message. With `BEDROCK_ENABLED` absent or not `true`, no model call or explanation field is added. Health and invalid-input requests never invoke Bedrock.

## IAM and Networking

Terraform adds `clinical-trial-site-risk-monitor-dev-eks-risk-service`, restricted by an operator-managed permissions boundary to `bedrock:InvokeModel` on the exact in-region Nova Micro foundation-model ARN. It cannot invoke other models or access storage. Converse uses the `bedrock:InvokeModel` IAM permission.

The role reuses the cluster's existing OIDC provider. Its trust requires audience `sts.amazonaws.com` and the exact subject `system:serviceaccount:clinical-trial-site-risk-monitor-demo:clinical-trial-risk-service`. The application uses the corresponding annotated Kubernetes service account. [IRSA supplies temporary AWS credentials](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html) through the EKS-injected web-identity token. Kubernetes API token automount remains disabled; the AWS token is a separate projection. The SDK refreshes credentials. Instance-metadata credential discovery is disabled in the app pod.

Streamlit's dedicated key still invokes only the assessment API; it gains no Bedrock permission. Worker, CNI, Lambda, and verification-job identities gain no model permissions. The main-only workflow can manage the named application role only with its required boundary and cannot edit that operator-owned boundary. No additional access keys are created for Bedrock.

The worker's existing public-subnet outbound path reaches regional STS and Bedrock over HTTPS. No VPC, NAT gateway, worker, model deployment, or paid private endpoint is added. If the network or role is unavailable, scoring still works and the optional summary is unavailable.

## Timeouts

The SDK applies a 1-second connect timeout, 3-second read timeout, and one total attempt, including default STS client configuration. Lambda allows 12 seconds for the backend, its own timeout is 18 seconds, API integration timeout is 20 seconds, and the UI HTTP timeout is 25 seconds. FastAPI runs the blocking SDK call in a worker thread so health remains responsive. These are socket/request limits, not a guarantee of identical total latency on every request.

## Deployment

All infrastructure changes use Terraform/Terragrunt. The operator first reviews/applies the `infrastructure/live/dev/github-actions` saved plan to create the exact model boundary and permit bounded application-role management. This prerequisite has been applied; CI cannot grant those permissions to itself.

After merging this feature:

1. Run **Lambda CI and dev deployment** on `main`, with **publish_image** and **deploy** checked and **disconnect_backend** unchecked. Wait for both image publication and Lambda deployment to succeed. This publishes the tested Bedrock-capable container and deploys Lambda's optional-field forwarding and longer timeouts.
2. Copy the full 40-character `main` commit SHA used by that publishing run. Run **Deploy EKS and risk service** on `main` with **deploy** checked and that exact **image_commit**. Terraform creates/updates the bounded application role, service account, and digest-pinned deployment; it does not add workers.
3. The in-cluster verifier requires an available Nova Micro explanation as well as the existing High result and five reasons. A legacy image or unavailable model fails this deployment check even though ordinary requests can still return scores during an AI outage. Existing resources remain running for diagnosis; there is no automatic destroy.
4. Allow Community Cloud to deploy the merged UI code. Existing Streamlit Secrets do not need a Bedrock key or model permission. Submit the sample and expect **High**, five rule-based reasons, and a separate **AI explanation** section. Test a Medium and Low sample too.

The EKS rollout and hosted verification are complete. The architecture image now shows Bedrock and the hosted Streamlit connection as active; Snowflake remains planned.

## Verification

Offline tests cover identifier exclusion, output limits, disabled mode, model failures, unchanged scores, Lambda forwarding, UI success/fallback, and the deployment's explanation gate. Mocked Terraform tests cover the exact model permission, boundary, service-account trust, non-root pod hardening, and timeout order. The container builds and passes HTTP health, sample assessment, and invalid-input checks in both disabled mode and enabled mode without credentials; the latter returns a valid risk result and an unavailable explanation.

The real Nova Micro model returned explanations for synthetic High, Medium, and Low cases. The actual FastAPI route also passed all three using operator credentials locally, with observed response times of approximately 0.4-1.1 seconds. No site identifiers were submitted to Bedrock. After the main-branch rollout, live API tests also returned the expected High, Medium, and Low scores with available Nova Micro explanations. The hosted Streamlit AI response was confirmed by the operator.

The reviewed operator Terraform plans have created the exact model boundary and IRSA role/policy, and updated only the existing bounded deployment-role policy. Running pods, workers, and network resources were not changed. IAM simulation allows Nova Micro and denies Nova Pro. Access Analyzer returned zero findings on the identity policies; its audience-claim suggestion on the trust policy was checked against [AWS's documented exact EKS aud/sub pattern](https://docs.aws.amazon.com/eks/latest/userguide/associate-service-account-role.html). The application service account and updated container have since been deployed through the EKS workflow.

Verified release: `4ca04378feedc3acd64aa37de06829232cdca634`. Both the [image/Lambda deployment](https://github.com/rohitjain2021/clinical-trial-site-risk-monitor/actions/runs/40404411193) and [EKS deployment with explanation verification](https://github.com/rohitjain2021/clinical-trial-site-risk-monitor/actions/runs/40405191261) succeeded.

## Assessment Notifications

The application can publish a minimal status event after a Bedrock attempt using an in-process background task. The same pod role has a separate exact-topic `sns:Publish` policy capped by its operator-managed boundary. Risk responses and model-failure fallback remain unchanged. See the [SNS notification guide](notifications.md) for rollout and confirmation.
