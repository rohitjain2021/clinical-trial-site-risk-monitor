"""Verify either the Kubernetes Service or private ALB using synthetic site data."""

import json
import os
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


def main():
    """Wait for private routing, then verify health, risk output, caching, and rejection.

    Both Terraform jobs run this same code so the ALB must preserve the existing
    FastAPI contract. Bounded startup retries accommodate endpoint propagation.
    """
    base = os.environ.get("API_BASE_URL", "http://clinical-trial-risk-service:8000")
    attempts = int(os.environ.get("HEALTH_ATTEMPTS", "12"))
    for attempt in range(attempts):
        try:
            with urlopen(base + "/health", timeout=3) as response:
                assert response.status == 200 and json.load(response)["status"] == "ok"
            break
        except (URLError, TimeoutError):
            if attempt == attempts - 1:
                raise
            time.sleep(2)
    request = Request(base + "/site-assessments", data=os.environ["SITE_JSON"].encode(),
                      headers={"Content-Type": "application/json"})
    with urlopen(request, timeout=10) as response:
        result = json.load(response)
        assert response.status == 200 and result["risk_level"] == "High" and len(result["reasons"]) == 5
        assert response.headers["Cache-Control"] == "no-store"
        if os.environ.get("REQUIRE_EXPLANATION") == "true":
            explanation = result.get("explanation", {})
            assert explanation.get("status") == "available", "Nova Micro explanation was not available"
            assert explanation.get("model_id") == "amazon.nova-micro-v1:0"
            assert isinstance(explanation.get("text"), str) and 0 < len(explanation["text"].strip()) <= 2000
    try:
        urlopen(Request(base + "/site-assessments", data=b"{}",
                        headers={"Content-Type": "application/json"}), timeout=10)
    except HTTPError as error:
        with error:
            assert error.code == 400
    else:
        raise AssertionError("Invalid assessment was accepted")
    print("Private health, assessment, cache-control, and invalid-input checks passed.")


if __name__ == "__main__":
    main()
