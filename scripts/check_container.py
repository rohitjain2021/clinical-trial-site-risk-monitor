"""Check the built FastAPI image over real HTTP without AWS or extra packages."""

import json
from pathlib import Path
import subprocess
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from uuid import uuid4


def check_container():
    """Run an isolated container and verify its API before deployment.

    Use a random loopback port and synthetic data to test the actual image.
    Always remove this test's container, including when an assertion fails.
    """
    name = f"clinical-trial-risk-check-{uuid4().hex}"
    try:
        subprocess.run([
            "docker", "run", "--detach", "--name", name,
            "--publish", "127.0.0.1::8000", "--read-only", "--tmpfs", "/tmp",
            "--cap-drop", "ALL", "--security-opt", "no-new-privileges:true",
            "clinical-trial-risk-service:local",
        ], check=True, timeout=60)
        info = json.loads(subprocess.check_output(
            ["docker", "inspect", name], text=True, timeout=15,
        ))[0]
        port = info["NetworkSettings"]["Ports"]["8000/tcp"][0]
        assert port["HostIp"] == "127.0.0.1"
        assert info["Config"]["User"] == "10001:10001"
        assert info["HostConfig"]["ReadonlyRootfs"]
        base = f"http://127.0.0.1:{port['HostPort']}"

        # Allow startup time, but fail predictably if the image cannot serve HTTP.
        for attempt in range(30):
            try:
                with urlopen(base + "/health", timeout=2) as response:
                    assert response.status == 200
                    health = json.load(response)
                    assert health["status"] == "ok"
                    assert health["rules_version"] == "prototype-v1"
                break
            except (OSError, URLError):
                time.sleep(1)
        else:
            raise RuntimeError("Container health check did not become ready.")
        print("GET /health: 200, status ok", flush=True)

        example = Path(__file__).resolve().parents[1] / "docs/examples/site-assessment.json"
        request = Request(base + "/site-assessments", data=example.read_bytes(),
                          headers={"Content-Type": "application/json"})
        with urlopen(request, timeout=5) as response:
            assert response.status == 200
            assert response.headers["Cache-Control"] == "no-store"
            result = json.load(response)
            assert result["site_id"] == json.loads(example.read_text())["site_id"]
            assert result["risk_level"] == "High"
            assert result["rules_version"] == "prototype-v1"
            assert len(result["reasons"]) == 5
        print("POST /site-assessments: 200, High risk, five reasons, no-store", flush=True)

        try:
            with urlopen(Request(base + "/site-assessments", data=b"{}",
                                 headers={"Content-Type": "application/json"}), timeout=5):
                raise AssertionError("Invalid assessment was accepted.")
        except HTTPError as error:
            assert error.code == 400
        print("Invalid assessment: 400; restricted runtime verified", flush=True)
    finally:
        # The unique name limits cleanup to this test, even if docker run failed.
        subprocess.run(["docker", "logs", name], check=False, timeout=15)
        subprocess.run(["docker", "rm", "--force", name], check=True, timeout=30)


if __name__ == "__main__":
    check_container()
