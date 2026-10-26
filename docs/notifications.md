# Assessment Email Notifications

This small demo publishes an SNS event after each valid site assessment that attempts a Bedrock explanation. The email reports the operational risk level, whether the explanation was generated or unavailable, the model name, and a UTC timestamp. It excludes site names/IDs, raw submissions, calculated reasons, model output, and credentials.

## Flow

```text
User selects Assess site
  -> FastAPI validates and calculates risk
  -> Bedrock explanation is attempted
  -> Assessment response returns
  -> Background task publishes to Amazon SNS
  -> Confirmed email subscriber receives the event
```

Health probes, invalid submissions, and assessments with Bedrock disabled do not notify. Both successful and unavailable explanations notify when a topic is configured. Each assessment makes one publish attempt, including valid verification-job or demo requests. Notification failures are logged generically and do not change the HTTP result or risk rating.

## Minimal Infrastructure

The operator-run `infrastructure/live/dev/notifications` Terragrunt unit provisions:

- Standard topic `clinical-trial-site-risk-monitor-dev-assessments`.
- A resource policy denying publishing without HTTPS; it grants no public access.
- One email subscription requiring the recipient's confirmation.

The existing EKS application role gains only `sns:Publish` on that exact topic, capped by its operator-managed permissions boundary. It retains the existing exact Nova Micro permission. UI, Lambda, worker, and CNI roles receive no SNS permissions. The application receives only the topic ARN, never the subscriber address. No extra Lambda, queue, agent, dashboard, alarm, or worker is added.

## Private Recipient and Terraform

Copy `infrastructure/live/dev/notifications/notifications.local.hcl.example` to ignored `notifications.local.hcl` and set the recipient locally. Never commit an actual address. The email variable is sensitive; its value remains in the access-restricted encrypted Terraform state at `dev/notifications/terraform.tfstate`. The GitHub deployment role cannot read this unit's state or manage the subscription.

Review and apply the saved operator plan:

```powershell
terragrunt --non-interactive --working-dir infrastructure/live/dev/notifications init
terragrunt --non-interactive --working-dir infrastructure/live/dev/notifications plan -out="$PWD/infrastructure/state/notifications.tfplan"
terragrunt --non-interactive --working-dir infrastructure/live/dev/notifications apply "$PWD/infrastructure/state/notifications.tfplan"
```

AWS sends a confirmation email; the recipient must click **Confirm subscription**. Until confirmed, assessment messages are not delivered to that address. See [SNS email setup](https://docs.aws.amazon.com/sns/latest/dg/sns-email-notifications.html). Unconfirmed email subscriptions also have deletion limitations documented by the [Terraform provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription).

## Application and Rollout

`services/risk_service/notifications.py` uses the existing Boto3 dependency and refreshable pod credentials. `ASSESSMENT_SNS_TOPIC_ARN` enables publishing. The client uses regional SNS with a one-second connect timeout, two-second read timeout, and one attempt; default STS calls share that bounded configuration. FastAPI schedules the synchronous publisher through its [background-task support](https://fastapi.tiangolo.com/tutorial/background-tasks/) after returning the response.

The operator first applies reviewed changes in `github-actions` for the exact SNS permissions boundary and `eks` for the application's publisher policy/output. These changes do not update workers or running pods. Then, after this code is merged:

1. Run **Lambda CI and dev deployment** on `main` with **publish_image** checked and **deploy** unchecked to publish the tested new container. This feature does not require a Lambda change.
2. Run **Deploy EKS and risk service** on `main` with **deploy** checked and the full commit SHA of that published image. The app receives the exact topic ARN and uses the updated container. Its verification assessment can also generate an email.
3. In Streamlit, submit a synthetic example and look for **Clinical Trial Risk Monitor - assessment processed** in the subscriber inbox. No Streamlit Secrets change is required.

## Demonstration and Monitoring

For a short demo: submit one report, show the risk result and AI text in Streamlit, then show the status email. SNS automatically exposes `NumberOfMessagesPublished`, `NumberOfNotificationsDelivered`, and `NumberOfNotificationsFailed` under CloudWatch's `AWS/SNS` namespace, filtered by the project topic name. See [SNS monitoring](https://docs.aws.amazon.com/sns/latest/dg/sns-monitoring-using-cloudwatch.html). No custom CloudWatch alarm is needed to send every-assessment notifications.

A successful publish means SNS accepted the message; it does not prove inbox delivery. The in-process task is best effort and can be lost if its process exits; standard SNS delivery can occasionally duplicate messages. This intentionally small demo does not provide a durable outbox or exactly-once delivery. It monitors assessments through this application, not unrelated Bedrock calls from the AWS console or other applications.

## Verification

Unit tests cover the exact topic, minimal message content, successful/unavailable AI events, disabled/invalid inputs, safe failure logging, and preserving the real FastAPI response after an SNS timeout. Mocked Terraform tests cover email confirmation, the HTTPS-only resource policy, exact IAM scope, and the topic environment variable. Container tests run without live SNS settings, so CI never sends email.

The diagram keeps the notification branch marked planned until the new application image is deployed and the hosted assessment-to-email flow is verified. The infrastructure and local integration verification status should be recorded separately from the production rollout.

## Verified Setup Status

The reviewed Terraform plans created the topic, transport policy, and subscription, updated the application permissions boundary, and added the exact publisher policy. The recipient confirmed the subscription. Access Analyzer reported zero findings on the IAM/topic policies, and IAM simulation allowed the project topic while denying an unrelated topic.

A real local FastAPI assessment called Nova Micro, returned High with five reasons and an available explanation, and published its status event. The recipient confirmed receipt of the demo email. The new image is not yet deployed on EKS; hosted assessment notifications remain pending the post-merge publication/deployment steps above.
