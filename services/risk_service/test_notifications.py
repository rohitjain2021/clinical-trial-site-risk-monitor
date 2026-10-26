"""Verify minimal, best-effort SNS events without sending email or using AWS."""

import os
import unittest
from unittest.mock import patch

from botocore.exceptions import ClientError, ReadTimeoutError

from services.risk_service.notifications import notify_assessment

TOPIC = "arn:aws:sns:us-east-1:123456789012:clinical-trial-site-risk-monitor-dev-assessments"


@patch.dict(os.environ, {"ASSESSMENT_SNS_TOPIC_ARN": TOPIC})
class NotificationTests(unittest.TestCase):
    """Keep events status-only and ensure notification errors remain nonfatal."""

    @patch("services.risk_service.notifications.notification_client")
    def test_publish_status_without_site_data(self, client):
        """Publish the exact topic once per attempt with a useful success/failure email."""
        for status, expected in (("available", "Generated successfully"), ("unavailable", "Unavailable")):
            client.return_value.publish.reset_mock()
            self.assertTrue(notify_assessment("High", status))
            client.return_value.publish.assert_called_once()
            message = client.return_value.publish.call_args.kwargs
            self.assertEqual(message["TopicArn"], TOPIC)
            self.assertIn("Risk level: High", message["Message"])
            self.assertIn(expected, message["Message"])
            self.assertIn("Processed at (UTC):", message["Message"])
            self.assertNotIn("site_id", message["Message"])
            self.assertNotIn("site_name", message["Message"])
            self.assertNotIn("reasons", message["Message"])
            self.assertNotIn("@", message["Message"])

    @patch("services.risk_service.notifications.notification_client")
    def test_missing_or_invalid_configuration_does_not_send(self, client):
        """Allow a local demo without SNS and refuse unrelated topics or untrusted statuses."""
        with patch.dict(os.environ, {"ASSESSMENT_SNS_TOPIC_ARN": ""}):
            self.assertFalse(notify_assessment("High", "available"))
        with patch.dict(os.environ, {"ASSESSMENT_SNS_TOPIC_ARN": "arn:aws:sns:us-east-1:123456789012:unrelated"}):
            self.assertFalse(notify_assessment("High", "available"))
        self.assertFalse(notify_assessment("private-site-data", "available"))
        self.assertFalse(notify_assessment("High", "private-model-data"))
        client.assert_not_called()

    @patch("services.risk_service.notifications.notification_client")
    def test_publish_errors_are_nonfatal_and_sanitized(self, client):
        """Never leak AWS errors or let email delivery failures break the scoring response."""
        for error in (ClientError({"Error": {"Code": "AccessDenied", "Message": "PRIVATE"}}, "Publish"), ReadTimeoutError(endpoint_url="https://private.example")):
            client.return_value.publish.side_effect = error
            with self.assertLogs("uvicorn.error", level="WARNING") as logs:
                self.assertFalse(notify_assessment("Low", "unavailable"))
            self.assertNotIn("PRIVATE", str(logs.output))
            self.assertNotIn("private.example", str(logs.output))
