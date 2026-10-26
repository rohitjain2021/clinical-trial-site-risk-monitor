"""Protect owned infrastructure while keeping EKS deployment explicit and simple."""

import unittest
from unittest.mock import patch

from scripts.deploy_eks import main, validate_plan


class DeploymentSafetyTests(unittest.TestCase):
    """Check deployment boundaries and the default plan-only behavior."""

    def plan(self, address, actions):
        """Build a small change fixture to exercise Terraform action validation."""
        return {"resource_changes": [{"mode": "managed", "address": address,
                                      "change": {"actions": actions}}]}

    def test_owned_creation(self):
        """Allow provisioning the exact project cluster through its Terraform unit."""
        validate_plan(self.plan("aws_eks_cluster.this", ["create"]), "eks")

    def test_no_deletion_or_replacement(self):
        """Require separate operator review before destructive infrastructure changes."""
        for actions in (["delete"], ["delete", "create"]):
            with self.assertRaises(ValueError):
                validate_plan(self.plan("aws_eks_cluster.this", actions), "eks")

    def test_no_shared_network_changes(self):
        """Keep the existing default VPC outside the deployment's ownership."""
        with self.assertRaises(ValueError):
            validate_plan(self.plan("aws_vpc.default", ["update"]), "eks")

    def test_repeatable_verification(self):
        """Refresh the HTTP test job without replacing the service or its infrastructure."""
        validate_plan(self.plan("kubernetes_job_v1.verify", ["delete", "create"]), "demo-app")

    @patch.dict("os.environ", {"GITHUB_REF": "refs/heads/feature"})
    def test_main_only(self):
        """Reject feature-branch execution before requesting AWS access."""
        with self.assertRaisesRegex(ValueError, "only on main"):
            main()

    @patch("scripts.deploy_eks.wait_for_access")
    @patch("scripts.deploy_eks.deploy_unit")
    @patch("scripts.deploy_eks.prepare_configuration")
    @patch("scripts.deploy_eks.run", return_value='{"imageDetails":[{"imageDigest":"sha256:' + "a" * 64 + '"}]}')
    @patch.dict("os.environ", {"GITHUB_REF": "refs/heads/main", "DEPLOY": "false", "IMAGE_COMMIT": "a" * 40})
    def test_plan_does_not_deploy_application(self, run, configure, deploy, access):
        """Plan-only runs must not provision EKS or contact a missing Kubernetes API."""
        main()
        deploy.assert_called_once_with("eks", False)
        access.assert_not_called()

    @patch("scripts.deploy_eks.wait_for_access")
    @patch("scripts.deploy_eks.deploy_unit", side_effect=RuntimeError("apply failed"))
    @patch("scripts.deploy_eks.prepare_configuration")
    @patch("scripts.deploy_eks.run", return_value='{"imageDetails":[{"imageDigest":"sha256:' + "a" * 64 + '"}]}')
    @patch.dict("os.environ", {"GITHUB_REF": "refs/heads/main", "DEPLOY": "true", "IMAGE_COMMIT": "a" * 40})
    def test_failure_does_not_destroy(self, run, configure, deploy, access):
        """Leave Terraform-managed resources for diagnosis instead of tearing them down on failure."""
        with self.assertRaisesRegex(RuntimeError, "apply failed"):
            main()
        deploy.assert_called_once_with("eks", True)
        access.assert_not_called()


if __name__ == "__main__":
    unittest.main()
