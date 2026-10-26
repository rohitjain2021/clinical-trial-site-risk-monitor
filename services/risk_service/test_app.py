"""Exercise the local service over HTTP without AWS, containers, or storage."""

import json
from pathlib import Path
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

from services.risk_service.app import app


class AppTests(unittest.TestCase):
    """Check the service's request contract independently of infrastructure."""

    def setUp(self):
        """Use an in-process HTTP client and synthetic site data for each test."""
        self.client = TestClient(app)
        path = Path(__file__).resolve().parents[2] / "docs/examples/site-assessment.json"
        self.site = json.loads(path.read_text())

    def test_health(self):
        """Confirm the service can report its health and prototype rule version."""
        response = self.client.get("/health")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["status"], "ok")
        self.assertEqual(response.json()["rules_version"], "prototype-v1")

    @patch("services.risk_service.app.explain_risk")
    def test_explanation_success_and_failure_preserve_rules(self, explain):
        """Return AI text separately, preserving risk results when the model fails."""
        for status, text in (("available", "High risk reflects the supplied operational concerns."), ("unavailable", None)):
            explain.return_value = {"status": status, "text": text, "model_id": "amazon.nova-micro-v1:0"}
            response = self.client.post("/site-assessments", json=self.site)
            self.assertEqual(response.status_code, 200)
            result = response.json()
            self.assertEqual(result["risk_level"], "High")
            self.assertEqual(len(result["reasons"]), 5)
            self.assertEqual(result["explanation"]["status"], status)
        explain.reset_mock()
        self.assertEqual(self.client.post("/site-assessments", json={}).status_code, 400)
        self.client.get("/health")
        explain.assert_not_called()

    def test_example_assessment(self):
        """The documented example must return High risk with its five reasons."""
        response = self.client.post("/site-assessments", json=self.site)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.headers["cache-control"], "no-store")
        result = response.json()
        self.assertEqual(result["site_id"], self.site["site_id"])
        self.assertEqual(result["risk_level"], "High")
        self.assertEqual(result["rules_version"], "prototype-v1")
        self.assertEqual(len(result["reasons"]), 5)

    def test_low_and_medium_assessments(self):
        """Verify HTTP responses for representative Low and Medium site records."""
        for enrolled, expected in ((60, "Low"), (42, "Medium")):
            with self.subTest(enrolled=enrolled):
                site = {**self.site, "actual_enrollment": enrolled,
                        "days_behind_schedule": 0, "patient_dropout_count": 0,
                        "protocol_deviation_count": 0, "unresolved_issue_count": 0}
                response = self.client.post("/site-assessments", json=site)
                self.assertEqual(response.status_code, 200)
                self.assertEqual(response.json()["risk_level"], expected)

    def test_invalid_records_do_not_echo_input(self):
        """Reject unsafe or invalid contract data without reflecting submitted values."""
        marker = "DO-NOT-ECHO-SYNTHETIC-MARKER"
        invalid = [{}, [], None, {**self.site, "actual_enrollment": True},
                   {**self.site, "enrollment_target": 0}, {**self.site, "unexpected": marker}]
        for site in invalid:
            with self.subTest(site=site):
                response = self.client.post("/site-assessments", content=json.dumps(site),
                                            headers={"Content-Type": "application/json"})
                self.assertEqual(response.status_code, 400)
                self.assertNotIn(marker, response.text)
                self.assertNotIn("risk_level", response.json())

    def test_malformed_json_and_encoding(self):
        """Turn malformed or non-UTF-8 bodies into predictable client errors."""
        for body in (b"{", b"\xff"):
            with self.subTest(body=body):
                response = self.client.post("/site-assessments", content=body,
                                            headers={"Content-Type": "application/json"})
                self.assertEqual(response.status_code, 400)

    def test_content_type_and_body_limit(self):
        """Reject unsupported media and oversized submissions before calculation."""
        response = self.client.post("/site-assessments", content="{}")
        self.assertEqual(response.status_code, 415)
        response = self.client.post("/site-assessments", content="x" * 65537,
                                    headers={"Content-Type": "application/json"})
        self.assertEqual(response.status_code, 413)

    def test_unknown_route(self):
        """Unimplemented routes must not silently perform a site assessment."""
        self.assertEqual(self.client.get("/unknown").status_code, 404)


if __name__ == "__main__":
    unittest.main()
