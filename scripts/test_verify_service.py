"""Exercise the shared real verifier without contacting a deployed backend."""

import importlib.util
import io
import json
import os
from pathlib import Path
import unittest
from unittest.mock import patch
from urllib.error import HTTPError, URLError

source = Path(__file__).resolve().parents[1] / "infrastructure/modules/demo-app/verify.py"
spec = importlib.util.spec_from_file_location("verify_service", source)
verify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify)


def response(body):
    """Build a context-managed HTTP response fixture for the verifier's contract checks."""
    result = io.BytesIO(json.dumps(body).encode())
    result.status = 200
    result.headers = {"Cache-Control": "no-store"}
    return result


@patch.dict(os.environ, {"SITE_JSON": '{"site_id":"synthetic"}',
                         "HEALTH_ATTEMPTS": "3", "API_BASE_URL": "http://alb.example.invalid"})
class VerificationTests(unittest.TestCase):
    """Check routing, bounded readiness, and rejection of incorrect API behavior."""

    @patch.object(verify.time, "sleep")
    @patch.object(verify, "urlopen")
    def test_transient_startup_then_real_checks(self, request, sleep):
        """Retry initial connectivity and run every contract check against the configured ALB URL."""
        request.side_effect = [URLError("starting"), response({"status": "ok"}),
                               response({"risk_level": "High", "reasons": ["synthetic"] * 5}),
                               HTTPError("http://alb.example.invalid", 400, "invalid", {}, None)]
        verify.main()
        urls = [c.args[0] if isinstance(c.args[0], str) else c.args[0].full_url for c in request.call_args_list]
        self.assertTrue(all(url.startswith("http://alb.example.invalid/") for url in urls))
        self.assertEqual(urls[-1], "http://alb.example.invalid/site-assessments")
        sleep.assert_called_once()

    @patch.object(verify.time, "sleep")
    @patch.object(verify, "urlopen", side_effect=URLError("unavailable"))
    def test_unavailable_backend_fails(self, request, sleep):
        """Never report a successful deployment when readiness remains unavailable."""
        with self.assertRaises(URLError):
            verify.main()
        self.assertEqual(request.call_count, 3)

    @patch.object(verify, "urlopen")
    def test_incorrect_risk_fails(self, request):
        """Reject an incorrect assessment even when the health endpoint works."""
        request.side_effect = [response({"status": "ok"}),
                               response({"risk_level": "Low", "reasons": []})]
        with self.assertRaises(AssertionError):
            verify.main()

    @patch.object(verify, "urlopen")
    def test_accepted_invalid_input_fails(self, request):
        """Require rejection of invalid records rather than accepting every HTTP 200."""
        request.side_effect = [response({"status": "ok"}),
                               response({"risk_level": "High", "reasons": ["synthetic"] * 5}),
                               response({})]
        with self.assertRaisesRegex(AssertionError, "Invalid assessment"):
            verify.main()


if __name__ == "__main__":
    unittest.main()
