"""HTTP contract and malformed-input checks without AWS dependencies."""

import base64
import json
import unittest

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

    def test_validation_does_not_claim_analysis(self):
        """Report validation only, without fabricated risk scores or echoed data."""
        response = lambda_handler(self.event(), None)
        self.assertEqual(response["statusCode"], 200)
        body = json.loads(response["body"])
        self.assertEqual(body["status"], "validated")
        self.assertNotIn("risk_score", body)
        self.assertNotIn("site_name", body)

    def test_reject_invalid_fields(self):
        """Reject invalid counts, zero targets, excess dropouts, and unknown data."""
        for field, value in (("actual_enrollment", -1), ("actual_enrollment", True),
                             ("enrollment_target", 0), ("patient_dropout_count", 22),
                             ("patient_name", "Unexpected"), ("site_id", "")):
            with self.subTest(field=field, value=value):
                event = self.event(json.dumps({**self.record, field: value}))
                self.assertEqual(lambda_handler(event, None)["statusCode"], 400)

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
