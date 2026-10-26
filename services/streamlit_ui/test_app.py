"""Verify server-side signing, safe errors, and the paste-and-assess UI."""

from io import BytesIO
import json
from pathlib import Path
import unittest
from unittest.mock import patch
from urllib.error import HTTPError, URLError

from streamlit.testing.v1 import AppTest
from services.streamlit_ui.app import assess_site

ROOT = Path(__file__).resolve().parents[2]
SAMPLE = (ROOT / "docs/examples/site-assessment.json").read_text()
RESULT = {"site_id": "SITE-001", "risk_level": "High", "rules_version": "prototype-v1", "reasons": ["Synthetic reason"]}
CONFIG = {
    "risk_api": {"base_url": "https://exampleapi.execute-api.us-east-1.amazonaws.com/dev"},
    "aws": {"access_key_id": "example", "secret_access_key": "synthetic-secret", "session_token": "synthetic-token"},
}


class StreamlitTests(unittest.TestCase):
    """Check real signing with fake credentials without contacting AWS or local FastAPI."""

    @patch("services.streamlit_ui.app.urlopen")
    def test_signed_cloud_request(self, http):
        """Sign the exact payload and route, preserving temporary-session tokens server-side."""
        http.return_value.__enter__.return_value.read.return_value = json.dumps(RESULT).encode()
        self.assertEqual(assess_site(SAMPLE, CONFIG), RESULT)
        request = http.call_args.args[0]
        self.assertEqual(request.full_url, CONFIG["risk_api"]["base_url"] + "/site-assessments")
        self.assertIn("AWS4-HMAC-SHA256", request.get_header("Authorization"))
        self.assertIn("/us-east-1/execute-api/aws4_request", request.get_header("Authorization"))
        self.assertEqual(request.get_header("X-amz-security-token"), "synthetic-token")
        self.assertEqual(json.loads(request.data), json.loads(SAMPLE))
        self.assertEqual(http.call_args.kwargs["timeout"], 10)

    @patch("services.streamlit_ui.app.urlopen")
    def test_local_mode_and_invalid_configuration(self, http):
        """Retain unsigned loopback calls and reject unsafe cloud endpoints before sending data."""
        http.return_value.__enter__.return_value.read.return_value = json.dumps(RESULT).encode()
        assess_site(SAMPLE, {})
        self.assertIsNone(http.call_args.args[0].get_header("Authorization"))
        http.reset_mock()
        for text, config in [("bad json", CONFIG), (SAMPLE, {"risk_api": {"base_url": "http://untrusted.example"}}), (SAMPLE, {**CONFIG, "aws": {"access_key_id": "example"}}), ('"' + "x" * 65536 + '"', CONFIG)]:
            with self.assertRaises(ValueError):
                assess_site(text, config)
        http.assert_not_called()

    @patch("services.streamlit_ui.app.urlopen")
    def test_errors_do_not_expose_private_details(self, http):
        """Show actionable status errors without leaking URLs, credentials, or response bodies."""
        for code in (400, 403, 503):
            http.side_effect = HTTPError("private-url", code, "private-detail", {}, BytesIO(b"private-secret"))
            with self.assertRaises(ValueError) as error:
                assess_site(SAMPLE, CONFIG)
            self.assertNotIn("private", str(error.exception))
        http.side_effect = URLError("private-url")
        with self.assertRaisesRegex(ValueError, "unavailable"):
            assess_site(SAMPLE, CONFIG)
        http.side_effect = None
        for body in (b"not json", b"{}", b"x" * 65537):
            http.return_value.__enter__.return_value.read.return_value = body
            with self.assertRaisesRegex(ValueError, "invalid response"):
                assess_site(SAMPLE, CONFIG)

    @patch("urllib.request.urlopen")
    def test_form_displays_risk_and_recovers_from_bad_json(self, http):
        """Exercise the real form in cloud mode, including correction after a failed submission."""
        http.return_value.__enter__.return_value.read.return_value = json.dumps(RESULT).encode()
        app = AppTest.from_file(str(ROOT / "services/streamlit_ui/app.py"))
        app.secrets.update(CONFIG)
        app.run()
        app.button[0].click().run()
        self.assertFalse(app.exception)
        self.assertEqual(app.metric[0].value, "High")
        app.text_area[0].set_value("bad json")
        app.button[0].click().run()
        self.assertTrue(app.error)
        self.assertFalse(app.metric)
        app.text_area[0].set_value(SAMPLE)
        app.button[0].click().run()
        self.assertEqual(app.metric[0].value, "High")
        self.assertFalse(app.exception)


if __name__ == "__main__":
    unittest.main()
