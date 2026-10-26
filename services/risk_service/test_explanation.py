"""Check optional model summaries without AWS calls or real trial data."""

import json
import os
import unittest
from unittest.mock import patch

from botocore.exceptions import ClientError, ReadTimeoutError

from services.risk_service.explanation import MODEL_ID, explain_risk


class ExplanationTests(unittest.TestCase):
    """Protect deterministic scores, bounded model use, and identifier exclusion."""

    def setUp(self):
        """Use a synthetic result and fresh mocked client with no credential lookup."""
        self.result = {"site_id": "PRIVATE-SITE-MARKER", "risk_level": "High",
                       "rules_version": "prototype-v1", "reasons": ["Enrollment is 35% of target."]}
        environment = patch.dict(os.environ, {"BEDROCK_ENABLED": "true"})
        environment.start()
        self.addCleanup(environment.stop)
        client = patch("services.risk_service.explanation.bedrock_client")
        self.client = client.start().return_value
        self.addCleanup(client.stop)
        self.client.converse.return_value = {
            "stopReason": "end_turn", "output": {"message": {"content": [{"text": "High operational risk reflects slow enrollment."}]}}
        }

    def test_bounded_summary_without_identifiers(self):
        """Use only calculated reasons, the exact model, and a short text output budget."""
        original = json.dumps(self.result, sort_keys=True)
        explanation = explain_risk(self.result)
        self.assertEqual(explanation["status"], "available")
        call = self.client.converse.call_args.kwargs
        self.assertEqual(call["modelId"], MODEL_ID)
        self.assertEqual(call["inferenceConfig"], {"maxTokens": 180, "temperature": 0})
        self.assertNotIn("PRIVATE-SITE-MARKER", json.dumps(call))
        self.assertEqual(set(json.loads(call["messages"][0]["content"][0]["text"])), {"risk_level", "rules_version", "reasons"})
        self.assertEqual(json.dumps(self.result, sort_keys=True), original)

    def test_disabled_does_not_contact_aws(self):
        """Keep local scoring usable without AWS credentials or model charges."""
        with patch.dict(os.environ, {"BEDROCK_ENABLED": "false"}):
            self.assertIsNone(explain_risk(self.result))
        self.client.converse.assert_not_called()

    def test_model_errors_are_unavailable(self):
        """Treat permission failures and timeouts as optional summary failures only."""
        for error in (ClientError({"Error": {"Code": "AccessDeniedException", "Message": "PRIVATE"}}, "Converse"), ReadTimeoutError(endpoint_url="https://private.example")):
            self.client.converse.side_effect = error
            explanation = explain_risk(self.result)
            self.assertEqual(explanation, {"status": "unavailable", "model_id": MODEL_ID, "text": None})
            self.assertEqual(self.result["risk_level"], "High")

    def test_truncated_empty_and_malformed_output(self):
        """Discard incomplete or oversized generations instead of presenting misleading text."""
        for reason, text in (("max_tokens", "partial"), ("content_filtered", "blocked"), ("end_turn", ""), ("end_turn", "x" * 2001), ("end_turn", None)):
            self.client.converse.return_value = {"stopReason": reason, "output": {"message": {"content": [{"text": text}]}}}
            self.assertEqual(explain_risk(self.result)["status"], "unavailable")
        self.client.converse.return_value = {}
        self.assertEqual(explain_risk(self.result)["status"], "unavailable")


if __name__ == "__main__":
    unittest.main()
