"""Write ignored Lambda settings from the existing ALB state without changing AWS."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def read_backend():
    """Read only the ALB state key; absence is allowed, but denied/incomplete reads fail closed."""
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "alb-state.json"
        try:
            result = subprocess.run([
                "aws", "s3api", "get-object", "--bucket", os.environ["PROJECT_TF_STATE_BUCKET"],
                "--key", "dev/alb/terraform.tfstate", str(path),
            ], capture_output=True, text=True, timeout=60)
        except subprocess.TimeoutExpired:
            raise RuntimeError("ALB state lookup timed out") from None
        if result.returncode:
            if "NoSuchKey" in result.stderr or "(404)" in result.stderr:
                return None
            raise RuntimeError("Cannot read ALB state; refusing to guess backend configuration")
        outputs = json.loads(path.read_text())["outputs"]
        if not outputs:
            return None
        required = {"api_base_url", "client_security_group_id", "subnet_ids"}
        if not required.issubset(outputs):
            raise RuntimeError("ALB outputs are incomplete; refresh the ALB Terraform outputs first")
        return {
            "url": outputs["api_base_url"]["value"],
            "subnet_ids": outputs["subnet_ids"]["value"],
            "security_group_id": outputs["client_security_group_id"]["value"],
        }


def configure_backend(disconnect=False):
    """Generate private Terraform inputs; explicit disconnect supports later backend teardown.

    An absent or destroyed ALB leaves the Lambda liveness route available. Only
    a boolean is exported to CI; endpoint and network identifiers stay private.
    """
    backend = None if disconnect else read_backend()
    path = ROOT / "infrastructure/live/dev/lambda/backend.local.hcl"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("locals {\n  backend = " + json.dumps(backend) + "\n}\n")
    enabled = "true" if backend else "false"
    if os.environ.get("GITHUB_ENV"):
        with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as output:
            output.write("RISK_BACKEND_ENABLED=" + enabled + "\n")
    print("Lambda backend enabled: " + enabled)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--disconnect", action="store_true")
    configure_backend(parser.parse_args().disconnect)
