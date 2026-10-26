"""Check private backend discovery without AWS access or real deployment identifiers."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from scripts.configure_lambda_backend import configure_backend, read_backend


class BackendConfigurationTests(unittest.TestCase):
    """Distinguish an absent backend from an unsafe or incomplete state read."""

    @patch.dict(os.environ, {"PROJECT_TF_STATE_BUCKET": "example-state-bucket"})
    @patch("scripts.configure_lambda_backend.subprocess.run")
    def test_read_exact_state_key(self, command):
        """Read only ALB state and map its private outputs to the Lambda input object."""
        outputs = {"api_base_url": {"value": "http://example.internal"},
                   "subnet_ids": {"value": ["subnet-a", "subnet-b"]},
                   "client_security_group_id": {"value": "sg-example"}}

        def download(arguments, **kwargs):
            """Write a synthetic state file where the mocked CLI would download it."""
            self.assertEqual(arguments[arguments.index("--key") + 1], "dev/alb/terraform.tfstate")
            Path(arguments[-1]).write_text(json.dumps({"outputs": outputs}))
            return subprocess.CompletedProcess(arguments, 0, "", "")

        command.side_effect = download
        self.assertEqual(read_backend()["security_group_id"], "sg-example")

    @patch.dict(os.environ, {"PROJECT_TF_STATE_BUCKET": "example-state-bucket"})
    @patch("scripts.configure_lambda_backend.subprocess.run")
    def test_missing_state_is_disconnected_but_denial_fails(self, command):
        """Allow initial health-only deployment while refusing to hide permission failures."""
        command.return_value = subprocess.CompletedProcess([], 1, "", "NoSuchKey")
        self.assertIsNone(read_backend())
        command.return_value = subprocess.CompletedProcess([], 1, "", "AccessDenied")
        with self.assertRaisesRegex(RuntimeError, "Cannot read"):
            read_backend()
        command.side_effect = subprocess.TimeoutExpired(["aws", "private-bucket"], 60)
        with self.assertRaisesRegex(RuntimeError, "lookup timed out"):
            read_backend()

    @patch("scripts.configure_lambda_backend.read_backend")
    def test_explicit_disconnect_skips_discovery(self, discover):
        """Write an explicit null backend so teardown does not need an available ALB."""
        with tempfile.TemporaryDirectory() as directory, patch("scripts.configure_lambda_backend.ROOT", Path(directory)), patch.dict(os.environ, {"GITHUB_ENV": ""}):
            configure_backend(disconnect=True)
            result = (Path(directory) / "infrastructure/live/dev/lambda/backend.local.hcl").read_text()
            self.assertIn("backend = null", result)
        discover.assert_not_called()


if __name__ == "__main__":
    unittest.main()
