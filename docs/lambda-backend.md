# Lambda to Private ALB

The authenticated API now validates a site record in Lambda, sends only its JSON data to the internal ALB, and returns FastAPI's `site_id`, `risk_level`, `rules_version`, and `reasons`. Risk rules remain in the existing service; Lambda does not duplicate scoring or store submissions.

## Network and IAM

Lambda uses the same two existing subnets as the ALB and only its dedicated client security group. That group has no ingress and permits outbound HTTP only to the ALB. No VPC, subnet, NAT gateway, public function URL, or additional EC2 worker is created. Lambda does not need internet access for this private call. Public API Gateway requests remain HTTPS with IAM/SigV4 authentication; the internal ALB hop currently uses HTTP.

AWS requires six EC2 actions on wildcard resources for Lambda-managed Hyperplane interfaces. Both the execution policy and operator-managed permissions boundary limit those actions to `us-east-1` and explicitly deny function-code EC2 calls using `lambda:SourceFunctionArn`. The Lambda service can create and release interfaces, while the handler cannot use these permissions. The GitHub deployment role can update only the named function in the selected default VPC/subnets, perform regional network discovery, and read the exact ALB state key. It cannot edit its own boundary. See [AWS VPC permissions and function-code protection](https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html).

## Private Configuration and Deployment

`scripts/configure_lambda_backend.py` reads only `dev/alb/terraform.tfstate` and writes ignored `infrastructure/live/dev/lambda/backend.local.hcl`. The ALB URL, two subnet IDs, and client group ID stay outside Git. A missing/destroyed ALB produces a null backend, while denied or incomplete state reads stop the deployment instead of guessing.

The Lambda workflow performs this discovery after OIDC authentication. With **deploy** checked and **disconnect_backend** unchecked, it plans and applies the existing Lambda using those settings. Pushes only plan. Terraform packages only the standard-library handler; no HTTP SDK dependency is added to Lambda. The ALB still has its separate operator provisioning unit.

The backend HTTP timeout is 12 seconds, Lambda timeout 18 seconds, and API integration timeout 20 seconds, allowing the optional Nova Micro explanation. Responses use `Cache-Control: no-store`. Invalid input is rejected before any backend call. Backend output size and fields are checked; errors omit internal endpoints and exception details. See [API responses and errors](api.md).

`GET /health` and direct `{}` invocation are Lambda liveness checks. They do not probe the backend. A valid assessment returns `503` when no backend is configured.

## Explicit Disconnect Before Teardown

There is no idle timer or automatic EKS teardown. When backend removal is explicitly requested:

1. Run **Lambda CI and dev deployment** on `main` with **deploy** and **disconnect_backend** checked. This retains Lambda/API, removes the backend URL and VPC attachment, and verifies liveness, assessment `503`, and unsigned denial.
2. Wait for AWS to release Lambda's interfaces from the dedicated client group before deleting that group. AWS documents that release can take up to 20 minutes. Keep the execution role, its ENI policy, and boundary in place during cleanup.
3. Apply reviewed destroy plans for ALB, application, and EKS, in that order. Retain ECR/images, Lambda/API, shared networking, IAM bootstrap, and state backend unless their removal is separately requested.

For operator-run Terraform, generate the null local configuration with `python scripts/configure_lambda_backend.py --disconnect`, then review and apply a saved Lambda plan. The script itself changes no AWS resources. After recreating EKS/application/ALB, rerun Lambda deployment with **disconnect_backend** unchecked to reconnect.

## Verification

The live operator deployment passed signed health and High/Medium/Low assessments through API Gateway → Lambda → ALB → EKS/FastAPI. Invalid data returned `400`, unsigned access `403`, and successful responses contained only the documented risk fields with no-store headers. One warm direct assessment reported 9.46 ms Lambda execution; three API round trips measured 210–601 ms. These are sample observations, not guarantees.

Local tests cover forwarding, credential exclusion, input validation, bounded body size, unavailable/disconnected backends, timeout/error sanitization, malformed results, site matching, and private configuration discovery. Mocked Terraform tests verify VPC attachment/disconnect, timeout ordering, IAM authentication, execution-role isolation, and deployment network restrictions. Access Analyzer returned zero findings; live IAM simulation allowed service ENI management, denied function-code ENI access, and denied deployment into unrelated VPCs/subnets.

The code and workflow changes must be merged before running the main-branch Lambda deployment workflow; an older checkout would use the previous validation-only handler.
