"""Verify server-side signing, safe errors, and the paste-and-assess UI."""

from io import BytesIO
import json
from pathlib import Path
import unittest
from unittest.mock import patch
from urllib.error import HTTPError, URLError

from streamlit.testing.v1 import AppTest
from services.streamlit_ui.app import assess_site, parse_report, sample_sites

ROOT = Path(__file__).resolve().parents[2]
SAMPLE = (ROOT / "docs/examples/site-assessment.json").read_text()
REPORT = (ROOT / "docs/examples/site-report.txt").read_text()
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
        self.assertEqual(http.call_args.kwargs["timeout"], 25)

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
    def test_form_displays_risk_and_recovers_from_bad_report(self, http):
        """Exercise report conversion, submitted metrics, and correction after a bad report."""
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
        self.assertNotIn("Risk level", [metric.label for metric in app.metric])
        app.text_area[0].set_value(REPORT)
        app.button[0].click().run()
        self.assertEqual(app.metric[0].value, "High")
        self.assertFalse(app.exception)
        self.assertEqual(json.loads(http.call_args.args[0].data), parse_report(REPORT))

    def test_report_parser_rejects_ambiguous_fields(self):
        """Reject missing, duplicate, unknown, negative, and fractional data without guessing."""
        record = parse_report(REPORT)
        self.assertEqual(record["actual_enrollment"], 21)
        self.assertEqual(record["site_name"], "Northbridge Research Center")
        self.assertEqual(parse_report(REPORT.replace("Site ID:", "SITE ID:")), record)
        for report in ("", "Patients enrolled: 21", REPORT + "\nPatients enrolled: 40", REPORT + "\nUnknown: 5",
                       REPORT.replace("Patient dropouts: 2", "Patient dropouts: -2"),
                       REPORT.replace("Patient dropouts: 2", "Patient dropouts: 1.5")):
            with self.assertRaises(ValueError):
                parse_report(report)

    @patch("urllib.request.urlopen")
    def test_manual_form_and_example_switch(self, http):
        """Submit numeric fields to the existing schema; example changes clear old results."""
        http.return_value.__enter__.return_value.read.return_value = json.dumps(RESULT).encode()
        app = AppTest.from_file(str(ROOT / "services/streamlit_ui/app.py"))
        app.secrets.update(CONFIG)
        app.run()
        http.assert_not_called()
        app.radio[0].set_value("Fill in fields").run()
        next(field for field in app.number_input if field.label == "Patients enrolled").set_value(30)
        app.button[0].click().run()
        self.assertFalse(app.exception)
        self.assertEqual(json.loads(http.call_args.args[0].data)["actual_enrollment"], 30)
        self.assertEqual(app.metric[0].value, "High")
        http.reset_mock()
        app.selectbox[0].select("Meeting operational targets").run()
        self.assertFalse(app.exception)
        http.assert_not_called()
        self.assertEqual(app.metric[0].value, "—")

    def test_synthetic_examples_cover_three_levels(self):
        """Keep meaningful example reports consistent with the real deterministic calculator."""
        from services.risk_service.risk import calculate_risk
        self.assertEqual([calculate_risk(site)["risk_level"] for site in sample_sites().values()], ["High", "Medium", "Low"])

    @patch("urllib.request.urlopen")
    def test_ai_text_and_unavailable_message(self, http):
        """Show model text separately and keep the score visible when AI is unavailable."""
        app = AppTest.from_file(str(ROOT / "services/streamlit_ui/app.py"))
        app.secrets.update(CONFIG)
        for status, text in (("available", "Synthetic AI summary."), ("unavailable", None)):
            http.return_value.__enter__.return_value.read.return_value = json.dumps({**RESULT, "explanation": {"status": status, "text": text, "model_id": "amazon.nova-micro-v1:0"}}).encode()
            app.run()
            app.button[0].click().run()
            self.assertFalse(app.exception)
            self.assertEqual(app.metric[0].value, "High")
            if status == "available":
                self.assertEqual(app.text[0].value, text)
            else:
                self.assertIn("unavailable", app.info[0].value)


if __name__ == "__main__":
    unittest.main()
