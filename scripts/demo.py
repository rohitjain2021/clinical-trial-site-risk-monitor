"""Start/stop the disposable FastAPI demo using only project Terraform units."""

import ipaddress
import base64
import json
import os
from pathlib import Path
import re
import subprocess
import sys
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
    },
    "demo-app": {
        "kubernetes_namespace_v1.demo", "kubernetes_deployment_v1.risk",
        "kubernetes_service_v1.risk", "kubernetes_job_v1.verify",
    },
}


def run(arguments, timeout=1800):
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
    """Run Terragrunt in one fixed demo unit so commands cannot target other stacks."""
    if unit not in ADDRESSES:
        raise ValueError("Unknown demo unit")
    return run(["terragrunt", "--non-interactive", "--working-dir",
                str(ROOT / "infrastructure/live/dev" / unit), *arguments])


def validate_plan(plan, unit, mode):
    """Reject unexpected resources and creation during Stop before any plan is applied."""
    for resource in plan.get("resource_changes", []):
        if resource["mode"] != "managed":
            continue
        address = resource["address"]
        actions = resource["change"]["actions"]
        if address not in ADDRESSES[unit]:
            raise ValueError("Plan contains a resource outside the demo allowlist")
        allowed = [["no-op"], ["delete"]] if mode == "stop" else [["no-op"], ["create"], ["update"]]
        if mode == "access":
            allowed = [["no-op"]] if address != "aws_eks_cluster.this" else [["no-op"], ["update"]]
        if mode == "start" and address == "kubernetes_job_v1.verify":
            allowed += [["delete", "create"], ["create", "delete"]]
        if actions not in allowed:
            raise ValueError("Unsafe plan actions; Stop never creates resources, and Start never replaces infrastructure")


def apply_plan(unit, mode):
    """Save, inspect, and apply a unit plan; Stop uses only reviewed destroy plans."""
    print(f"{mode}: {unit}", flush=True)
    tg(unit, "init", "-input=false", "-no-color")
    plan_path = Path(os.environ["RUNNER_TEMP"]) / f"demo-{unit}-{mode}.tfplan"
    arguments = ["plan", "-input=false", "-lock-timeout=60s", "-no-color", "-out=" + str(plan_path)]
    if mode == "stop":
        arguments += ["-destroy"]
    if mode == "access":
        # A new runner has a different /32; update only the existing API allowlist.
        arguments += ["-target=aws_eks_cluster.this"]
    tg(unit, *arguments)
    validate_plan(json.loads(tg(unit, "show", "-json", str(plan_path))), unit, mode)
    tg(unit, "apply", "-input=false", "-no-color", str(plan_path))
    plan_path.unlink()


def state_resources(unit):
    """Read only the unit's existing S3 state, treating an absent state as no demo."""
    path = Path(os.environ["RUNNER_TEMP"]) / f"demo-{unit}-state.json"
    result = subprocess.run([
        "aws", "s3api", "get-object", "--bucket", os.environ["PROJECT_TF_STATE_BUCKET"],
        "--key", f"dev/{unit}/terraform.tfstate", str(path),
    ], cwd=ROOT, capture_output=True, text=True, timeout=60)
    try:
        if result.returncode:
            if "NoSuchKey" in result.stderr or "(404)" in result.stderr:
                return []
            raise RuntimeError("Could not read demo state; refusing to guess whether cleanup is needed")
        return [r for r in json.loads(path.read_text())["resources"] if r["mode"] == "managed"]
    finally:
        path.unlink(missing_ok=True)


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


def stop():
    """Remove the application first, then EKS; an empty demo is a safe no-op."""
    eks = state_resources("eks")
    app = state_resources("demo-app")
    if app:
        if not any(r["type"] == "aws_eks_cluster" for r in eks):
            raise RuntimeError("Application state remains but its cluster is missing; operator recovery is required")
        apply_plan("eks", "access")
        wait_for_access()
        apply_plan("demo-app", "stop")
    if eks:
        apply_plan("eks", "stop")
    if state_resources("eks") or state_resources("demo-app"):
        raise RuntimeError("Demo state still contains resources; cleanup is incomplete")
    verify_cleanup()
    print("Demo stacks are empty; existing VPC, ECR, Lambda, and backend were preserved.", flush=True)


def verify_cleanup():
    """Check AWS directly for demo resources, including roles lost from interrupted state writes."""
    result = subprocess.run(["aws", "eks", "describe-cluster", "--name", CLUSTER],
                            cwd=ROOT, capture_output=True, text=True, timeout=60)
    if result.returncode == 0 or "ResourceNotFoundException" not in result.stderr:
        raise RuntimeError("Cluster deletion could not be confirmed; inspect AWS before assuming charges ended")
    for suffix in ("control-plane", "nodes", "vpc-cni"):
        result = subprocess.run(["aws", "iam", "get-role", "--role-name", f"{CLUSTER}-{suffix}"],
                                cwd=ROOT, capture_output=True, text=True, timeout=60)
        if result.returncode == 0 or "NoSuchEntity" not in result.stderr:
            raise RuntimeError("Demo IAM role cleanup could not be confirmed; recover leftovers into Terraform before retrying Start")
    instances = json.loads(run([
        "aws", "ec2", "describe-instances", "--filters",
        "Name=tag:Project,Values=clinical-trial-site-risk-monitor",
        f"Name=tag:Name,Values={CLUSTER}-risk-node",
        "Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down",
        "--output", "json",
    ]))["Reservations"]
    volumes = json.loads(run([
        "aws", "ec2", "describe-volumes", "--filters",
        "Name=tag:Project,Values=clinical-trial-site-risk-monitor",
        f"Name=tag:Name,Values={CLUSTER}-node-root", "--output", "json",
    ]))["Volumes"]
    if any(reservation["Instances"] for reservation in instances) or volumes:
        raise RuntimeError("Tagged demo workers or root volumes still exist; rerun Stop to verify cleanup")


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
    """Execute only the explicit main-branch Start/Stop choice; clean up failed starts."""
    if os.environ.get("GITHUB_REF") != "refs/heads/main":
        raise ValueError("Demo operations run only on main")
    action = os.environ["DEMO_ACTION"]
    if action not in {"start", "stop"}:
        raise ValueError("Choose start or stop")
    digest = "sha256:" + "0" * 64  # Valid unused placeholder for destroy-only inputs.
    if action == "start":
        commit = os.environ["DEMO_IMAGE_COMMIT"]
        if not re.fullmatch(r"[a-f0-9]{40}", commit):
            raise ValueError("Choose a full published commit SHA")
        detail = json.loads(run(["aws", "ecr", "describe-images", "--repository-name", REPOSITORY,
                                 "--image-ids", "imageTag=" + commit, "--output", "json"]))["imageDetails"][0]
        digest = detail["imageDigest"]
        if not re.fullmatch(r"sha256:[a-f0-9]{64}", digest):
            raise ValueError("ECR did not return a valid image digest")
    prepare_configuration(digest)
    if action == "stop":
        stop()
        return
    try:
        apply_plan("eks", "start")
        wait_for_access()
        apply_plan("demo-app", "start")
        print("FastAPI demo is ready privately; in-cluster HTTP verification passed. Run Stop when finished.", flush=True)
    except Exception:
        print("Start failed; attempting to remove the demo to avoid idle charges.", flush=True)
        try:
            stop()
        except Exception as cleanup_error:
            print("Automatic cleanup failed. Run Stop demo and inspect AWS: " + str(cleanup_error), file=sys.stderr)
        raise


if __name__ == "__main__":
    main()
