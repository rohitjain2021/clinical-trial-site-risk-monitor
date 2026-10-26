"""Export Terraform's sensitive UI settings into a Git-ignored local TOML file."""

import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def export_secrets():
    """Capture the scoped identity output without logging it, for Streamlit settings.

    Terraform owns the AWS identity and key. This only copies existing settings;
    it never creates credentials or copies the operator's AWS credentials.
    """
    result = subprocess.run([
        "terragrunt", "--non-interactive", "--working-dir",
        str(ROOT / "infrastructure/live/dev/streamlit-access"),
        "output", "-json", "app_secrets",
    ], capture_output=True, text=True, timeout=60)
    if result.returncode:
        raise RuntimeError("Cannot read Streamlit Terraform outputs; no credentials were exported.")
    config = json.loads(result.stdout)
    content = "\n\n".join(
        "[" + section + "]\n" + "\n".join(key + " = " + json.dumps(value) for key, value in values.items())
        for section, values in config.items()
    ) + "\n"
    path = ROOT / ".streamlit/secrets.toml"
    path.parent.mkdir(exist_ok=True)
    path.write_text(content, encoding="utf-8")
    print("Private settings saved to ignored .streamlit/secrets.toml. Copy them into Streamlit Settings > Secrets.")


if __name__ == "__main__":
    export_secrets()
