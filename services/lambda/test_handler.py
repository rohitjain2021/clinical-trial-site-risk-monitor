"""HTTP contract and malformed-input checks without AWS dependencies."""

import base64
import json
import os
import unittest
from unittest.mock import patch
from urllib.error import HTTPError, URLError

from handler import lambda_handler


class HandlerTests(unittest.TestCase):
    """Exercise client-visible behavior so validation failures stay predictable."""

    def setUp(self):
        """Build a synthetic aggregate record shared by independent API tests."""
        self.record = {
            "site_id": "SITE-001", "site_name": "Example Research Site",
            "enrollment_target": 60, "actual_enrollment": 21,
            "days_behind_schedule": 18, "patient_dropout_count": 2,
            "protocol_deviation_count": 1, "unresolved_issue_count": 3,
        }
        self.result = {"site_id": "SITE-001", "risk_level": "High", "rules_version": "prototype-v1", "reasons": ["Synthetic reason"]}
        environment = patch.dict(os.environ, {"RISK_API_URL": "http://backend.example.invalid"})
        environment.start()
        self.addCleanup(environment.stop)
        backend = patch("handler.urlopen")
        self.backend = backend.start()
        self.addCleanup(backend.stop)
        response = self.backend.return_value.__enter__.return_value
        response.status = 200
        response.read.return_value = json.dumps(self.result).encode()

    def event(self, body=None):
        """Construct the v2 event shape API Gateway sends to the POST handler."""
        return {
            "routeKey": "POST /site-assessments",
            "headers": {"Content-Type": "application/json; charset=utf-8"},
            "body": json.dumps(self.record) if body is None else body,
            "isBase64Encoded": False,
        }

    def test_health_and_direct_probe(self):
        """Keep both the HTTP health route and existing pipeline probe working."""
        for event in ({}, {"routeKey": "GET /health"}):
            with self.subTest(event=event):
                response = lambda_handler(event, None)
                self.assertEqual(response["statusCode"], 200)
                self.assertEqual(json.loads(response["body"])["status"], "ok")
        self.backend.assert_not_called()

    def test_returns_backend_assessment(self):
        """Return the real validated backend result and forward only the JSON site record."""
        response = lambda_handler(self.event(), None)
        self.assertEqual(response["statusCode"], 200)
        body = json.loads(response["body"])
        self.assertEqual(body, self.result)
        self.assertNotIn("site_name", body)
        request = self.backend.call_args.args[0]
        self.assertEqual(json.loads(request.data), self.record)
        self.assertNotIn("Authorization", request.headers)
        self.assertEqual(response["headers"]["Cache-Control"], "no-store")

    def test_optional_explanation_is_bounded_and_separate(self):
        """Pass only safe AI fields and keep the deterministic result on bad AI output."""
        backend = self.backend.return_value.__enter__.return_value
        for text in ("High operational risk reflects enrollment delays.", "x" * 2001, None):
            backend.read.return_value = json.dumps({**self.result, "explanation": {
                "status": "available", "model_id": "amazon.nova-micro-v1:0", "text": text,
                "private-extra": "DO-NOT-ECHO",
            }}).encode()
            response = lambda_handler(self.event(), None)
            self.assertEqual(response["statusCode"], 200)
            body = json.loads(response["body"])
            self.assertEqual(body["risk_level"], "High")
            self.assertNotIn("DO-NOT-ECHO", response["body"])
            self.assertEqual(body["explanation"]["status"], "available" if text and len(text) <= 2000 else "unavailable")

    def test_reject_invalid_fields(self):
        """Reject invalid counts, zero targets, excess dropouts, and unknown data."""
        for field, value in (("actual_enrollment", -1), ("actual_enrollment", True),
                             ("enrollment_target", 0), ("patient_dropout_count", 22),
                             ("patient_name", "Unexpected"), ("site_id", "")):
            with self.subTest(field=field, value=value):
                event = self.event(json.dumps({**self.record, field: value}))
                self.assertEqual(lambda_handler(event, None)["statusCode"], 400)
        self.backend.assert_not_called()

    def test_disconnected_backend_is_unavailable(self):
        """Keep a safe 503 instead of inventing an assessment when backend settings are absent."""
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(lambda_handler(self.event(), None)["statusCode"], 503)
        self.backend.assert_not_called()

    def test_backend_failures_are_sanitized(self):
        """Map timeout, connectivity and HTTP failures without exposing private exception details."""
        for error, status in [(TimeoutError("private-host"), 504),
                              (URLError("private-host"), 503),
                              (ConnectionResetError("private-host"), 503),
                              (URLError(TimeoutError("private-host")), 504),
                              (HTTPError("http://private-host", 500, "private-data", {}, None), 502)]:
            with self.subTest(status=status):
                self.backend.side_effect = error
                response = lambda_handler(self.event(), None)
                self.assertEqual(response["statusCode"], status)
                self.assertNotIn("private", response["body"])

    def test_invalid_backend_results_are_rejected(self):
        """Reject malformed, oversized, mismatched-site or incomplete backend output."""
        response = self.backend.return_value.__enter__.return_value
        for payload in [b"not-json", b"x" * 65537, b"[]",
                        json.dumps({**self.result, "site_id": "other-site"}).encode(),
                        json.dumps({**self.result, "risk_level": "Unknown"}).encode(),
                        json.dumps({**self.result, "reasons": []}).encode()]:
            with self.subTest(payload_length=len(payload)):
                response.read.return_value = payload
                self.assertEqual(lambda_handler(self.event(), None)["statusCode"], 502)

    def test_backend_extra_fields_are_not_exposed(self):
        """Whitelist the documented risk contract rather than trusting arbitrary backend fields."""
        self.backend.return_value.__enter__.return_value.read.return_value = json.dumps({**self.result, "internal": "private-data"}).encode()
        self.assertEqual(json.loads(lambda_handler(self.event(), None)["body"]), self.result)

    def test_reject_missing_or_nonobject_data(self):
        """The single-site endpoint must reject batches, missing fields, and null."""
        for body in ("{}", "[]", "null", "{"):
            with self.subTest(body=body):
                self.assertEqual(lambda_handler(self.event(body), None)["statusCode"], 400)

    def test_content_type_and_unknown_route(self):
        """Use distinct client error codes for unsupported content and routes."""
        event = self.event()
        event["headers"] = {}
        self.assertEqual(lambda_handler(event, None)["statusCode"], 415)
        self.assertEqual(lambda_handler({"routeKey": "DELETE /health"}, None)["statusCode"], 404)

    def test_encoded_and_oversized_bodies(self):
        """Handle API Gateway base64 encoding and bound validation memory usage."""
        event = self.event()
        event["body"] = base64.b64encode(event["body"].encode()).decode()
        event["isBase64Encoded"] = True
        self.assertEqual(lambda_handler(event, None)["statusCode"], 200)
        event["body"] = "not-base64!"
        self.assertEqual(lambda_handler(event, None)["statusCode"], 400)
        self.assertEqual(lambda_handler(self.event("x" * 65537), None)["statusCode"], 413)


if __name__ == "__main__":
    unittest.main()
