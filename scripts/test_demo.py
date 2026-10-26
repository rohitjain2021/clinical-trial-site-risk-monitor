"""Check the safety rules protecting demo Start and Stop operations."""

import unittest
from unittest.mock import call, patch

from scripts.demo import validate_plan, stop


class DemoSafetyTests(unittest.TestCase):
    """Reject destructive scope mistakes and ensure cleanup preserves stack order."""

    def plan(self, address, actions):
        """Build a minimal Terraform change fixture for action and ownership checks."""
        return {"resource_changes": [{"mode": "managed", "address": address, "change": {"actions": actions}}]}

    def test_stop_rejects_creation(self):
        """Stop must not recreate infrastructure when a state or runner has changed."""
        with self.assertRaises(ValueError):
            validate_plan(self.plan("aws_eks_cluster.this", ["create"]), "eks", "stop")

    def test_shared_network_is_never_allowed(self):
        """Reject a VPC in the destroy plan even if it was accidentally put in state."""
        with self.assertRaises(ValueError):
            validate_plan(self.plan("aws_vpc.default", ["delete"]), "eks", "stop")

    def test_stop_accepts_owned_deletion(self):
        """Allow deletion of the exact EKS cluster owned by this unit."""
        validate_plan(self.plan("aws_eks_cluster.this", ["delete"]), "eks", "stop")

    def test_start_rejects_cluster_replacement(self):
        """A Start operation must not silently replace an existing demo cluster."""
        with self.assertRaises(ValueError):
            validate_plan(self.plan("aws_eks_cluster.this", ["delete", "create"]), "eks", "start")

    def test_access_refresh_cannot_create_cluster(self):
        """Refreshing a runner allowlist must only update an existing cluster."""
        with self.assertRaises(ValueError):
            validate_plan(self.plan("aws_eks_cluster.this", ["create"]), "eks", "access")

    def test_fresh_verification_job(self):
        """Permit replacing only the completed health job to recheck every Start."""
        validate_plan(self.plan("kubernetes_job_v1.verify", ["delete", "create"]), "demo-app", "start")

    @patch("scripts.demo.wait_for_access")
    @patch("scripts.demo.verify_cleanup")
    @patch("scripts.demo.apply_plan")
    @patch("scripts.demo.state_resources")
    def test_stop_application_before_cluster(self, state, apply, verify, access):
        """Keep the Kubernetes API available until application destruction finishes."""
        state.side_effect = [[{"type": "aws_eks_cluster"}], [{"type": "kubernetes_deployment_v1"}], [], []]
        stop()
        self.assertEqual(apply.call_args_list, [call("eks", "access"), call("demo-app", "stop"), call("eks", "stop")])
        verify.assert_called_once()

    @patch("scripts.demo.verify_cleanup")
    @patch("scripts.demo.apply_plan")
    @patch("scripts.demo.state_resources", return_value=[])
    def test_empty_stop_does_not_apply(self, state, apply, verify):
        """A repeated Stop checks for leftovers without creating a fresh cluster."""
        stop()
        apply.assert_not_called()
        verify.assert_called_once()


if __name__ == "__main__":
    unittest.main()
