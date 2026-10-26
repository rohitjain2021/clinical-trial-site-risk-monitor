"""Plan or deploy EKS and the private FastAPI service through Terraform units."""

import ipaddress
import base64
import json
import os
from pathlib import Path
import re
import subprocess
import ssl
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]
CLUSTER = "clinical-trial-site-risk-monitor-dev-eks"
REPOSITORY = "clinical-trial-site-risk-monitor-dev-risk-service"
ADDRESSES = {
    "eks": {
        "aws_cloudwatch_log_group.cluster", "aws_eks_cluster.this",
        "aws_eks_access_entry.operator", "aws_eks_access_policy_association.operator",
        "aws_eks_access_entry.demo", "aws_eks_access_policy_association.demo",
        "aws_launch_template.nodes", "aws_eks_node_group.risk",
        'aws_eks_addon.core["vpc-cni"]', 'aws_eks_addon.core["kube-proxy"]',
        'aws_eks_addon.core["coredns"]', "aws_iam_role.cluster", "aws_iam_role.nodes",
        "aws_iam_role.cni", "aws_iam_role_policy_attachment.cluster",
        "aws_iam_role_policy_attachment.nodes", "aws_iam_role_policy_attachment.cni",
        "aws_iam_role_policy.node_images", "aws_iam_openid_connect_provider.cluster",
        "aws_iam_role.risk", "aws_iam_role_policy.bedrock",
    },
    "demo-app": {
        "kubernetes_namespace_v1.demo", "kubernetes_deployment_v1.risk",
        "kubernetes_service_v1.risk", "kubernetes_job_v1.verify",
        "kubernetes_service_account_v1.risk",
    },
}


def run(arguments, timeout=3000):
    """Capture command output privately; surface scrubbed errors for CI diagnosis."""
    result = subprocess.run(arguments, cwd=ROOT, capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        message = result.stdout + result.stderr
        for key, value in os.environ.items():
            if key.startswith("PROJECT_") and value:
                message = message.replace(value, "<private>")
        message = re.sub(r"\b\d{12}\b", "<account>", message)
        message = re.sub(r"\b(?:vpc|subnet|sg)-[0-9a-f]+\b", "<network-id>", message)
        message = re.sub(r"\b(?:\d{1,3}\.){3}\d{1,3}(?:/\d+)?\b", "<ip>", message)
        message = re.sub(r"https://[^\s\"']+\.eks\.amazonaws\.com", "<cluster-endpoint>", message)
        raise RuntimeError(f"{arguments[0]} failed:\n{message[-5000:]}")
    return result.stdout


def tg(unit, *arguments):
    """Run Terragrunt in one fixed deployment unit so commands cannot target other stacks."""
    if unit not in ADDRESSES:
        raise ValueError("Unknown deployment unit")
    return run(["terragrunt", "--non-interactive", "--working-dir",
                str(ROOT / "infrastructure/live/dev" / unit), *arguments])


def validate_plan(plan, unit):
    """Allow only owned creates/updates; protect infrastructure from deletion or replacement."""
    for resource in plan.get("resource_changes", []):
        if resource["mode"] != "managed":
            continue
        address = resource["address"]
        actions = resource["change"]["actions"]
        if address not in ADDRESSES[unit]:
            raise ValueError("Plan contains a resource outside the deployment allowlist")
        allowed = [["no-op"], ["create"], ["update"]]
        if address == "kubernetes_job_v1.verify":
            allowed += [["delete", "create"], ["create", "delete"]]
        if actions not in allowed:
            raise ValueError("Deployment cannot delete or replace infrastructure")


def deploy_unit(unit, apply):
    """Save and inspect a Terraform plan, then apply that same plan only when requested."""
    print(("Deploying: " if apply else "Planning: ") + unit, flush=True)
    tg(unit, "init", "-input=false", "-no-color")
    plan_path = Path(os.environ["RUNNER_TEMP"]) / f"deploy-{unit}.tfplan"
    try:
        tg(unit, "plan", "-input=false", "-lock-timeout=60s", "-no-color", "-out=" + str(plan_path))
        plan = json.loads(tg(unit, "show", "-json", str(plan_path)))
        validate_plan(plan, unit)
        changes = [r for r in plan.get("resource_changes", []) if r["mode"] == "managed" and r["change"]["actions"] != ["no-op"]]
        for resource in changes:
            print(resource["address"] + ": " + ", ".join(resource["change"]["actions"]), flush=True)
        if apply:
            tg(unit, "apply", "-input=false", "-no-color", str(plan_path))
    finally:
        plan_path.unlink(missing_ok=True)


def prepare_configuration(image_digest):
    """Write ignored settings with operator/runner /32 access and a digest-pinned image."""
    account = os.environ["PROJECT_AWS_ACCOUNT_ID"]
    if not re.fullmatch(r"\d{12}", account):
        raise ValueError("Invalid account configuration")
    with urlopen("https://checkip.amazonaws.com", timeout=15) as response:
        runner_ip = str(ipaddress.IPv4Address(response.read().decode().strip())) + "/32"
    operator_cidr = os.environ["PROJECT_EKS_ADMIN_CIDR"]
    if ipaddress.IPv4Network(operator_cidr).prefixlen != 32:
        raise ValueError("The operator allowlist must be a single /32")
    configurations = {
        "deployment.local.hcl": {
            "aws_account_id": account, "state_bucket": os.environ["PROJECT_TF_STATE_BUCKET"],
        },
        "eks/eks.local.hcl": {
            "admin_principal_arn": os.environ["PROJECT_EKS_ADMIN_PRINCIPAL_ARN"],
            "admin_cidrs": sorted({operator_cidr, runner_ip}),
        },
        "demo-app/demo.local.hcl": {
            "image_uri": f"{account}.dkr.ecr.us-east-1.amazonaws.com/{REPOSITORY}@{image_digest}",
            "verification_run_id": os.environ["GITHUB_RUN_ID"],
        },
    }
    for filename, values in configurations.items():
        path = ROOT / "infrastructure/live/dev" / filename
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("locals {\n" + "".join(f"  {key} = {json.dumps(value)}\n" for key, value in values.items()) + "}\n")
    print("::add-mask::" + runner_ip)


def wait_for_access():
    """Wait for API allowlist and access-entry propagation before Kubernetes Terraform."""
    cluster = json.loads(run(["aws", "eks", "describe-cluster", "--name", CLUSTER, "--output", "json"]))["cluster"]
    context = ssl.create_default_context(cadata=base64.b64decode(cluster["certificateAuthority"]["data"]).decode())
    token = json.loads(run(["aws", "eks", "get-token", "--cluster-name", CLUSTER, "--output", "json"]))["status"]["token"]
    request = Request(cluster["endpoint"] + "/api/v1/namespaces", headers={"Authorization": "Bearer " + token})
    for attempt in range(12):
        try:
            with urlopen(request, context=context, timeout=5) as response:
                if response.status == 200:
                    return
        except (HTTPError, URLError, TimeoutError):
            time.sleep(5)
    raise RuntimeError("Kubernetes access did not become ready; refusing to apply application changes")


def main():
    """Plan by default; explicitly deploy EKS then FastAPI without automatic destruction."""
    if os.environ.get("GITHUB_REF") != "refs/heads/main":
        raise ValueError("AWS deployment runs only on main")
    choice = os.environ.get("DEPLOY", "false")
    if choice not in {"true", "false"}:
        raise ValueError("DEPLOY must be true or false")
    apply = choice == "true"
    commit = os.environ["IMAGE_COMMIT"]
    if not re.fullmatch(r"[a-f0-9]{40}", commit):
        raise ValueError("Choose a full published commit SHA")
    detail = json.loads(run(["aws", "ecr", "describe-images", "--repository-name", REPOSITORY,
                             "--image-ids", "imageTag=" + commit, "--output", "json"]))["imageDetails"][0]
    digest = detail["imageDigest"]
    if not re.fullmatch(r"sha256:[a-f0-9]{64}", digest):
        raise ValueError("ECR did not return a valid image digest")
    prepare_configuration(digest)
    deploy_unit("eks", apply)
    if not apply:
        print("EKS plan complete. Select deploy to provision EKS, then plan and deploy FastAPI.", flush=True)
        return
    wait_for_access()
    deploy_unit("demo-app", True)
    print("FastAPI deployed privately; in-cluster HTTP verification passed. Resources remain running.", flush=True)


if __name__ == "__main__":
    main()
