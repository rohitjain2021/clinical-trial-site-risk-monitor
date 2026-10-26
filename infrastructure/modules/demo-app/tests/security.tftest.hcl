mock_provider "kubernetes" {}

variables {
  cluster_name        = "example-cluster"
  cluster_endpoint    = "https://example.invalid"
  cluster_certificate = "ZXhhbXBsZQ=="
  image_uri           = "123456789012.dkr.ecr.us-east-1.amazonaws.com/clinical-trial-site-risk-monitor-dev-risk-service@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  site_example_json   = "{}"
  verification_run_id = "test-run"
}

run "private_hardened_demo" {
  command = plan
  assert {
    condition     = !alltrue([for key, value in kubernetes_service_v1.risk.spec[0].selector : lookup(kubernetes_job_v1.verify.spec[0].template[0].metadata[0].labels, key, "") == value]) && alltrue([for key, value in kubernetes_service_v1.risk.spec[0].selector : lookup(kubernetes_deployment_v1.risk.spec[0].template[0].metadata[0].labels, key, "") == value])
    error_message = "The Service must select application pods and exclude the verification client pod."
  }
  assert {
    condition     = kubernetes_service_v1.risk.spec[0].type == "ClusterIP" && kubernetes_deployment_v1.risk.spec[0].replicas == "1" && kubernetes_deployment_v1.risk.wait_for_rollout && kubernetes_job_v1.verify.wait_for_completion
    error_message = "Keep the demo private and wait for rollout plus real HTTP verification."
  }
  assert {
    condition     = kubernetes_deployment_v1.risk.spec[0].template[0].spec[0].security_context[0].run_as_non_root && !kubernetes_deployment_v1.risk.spec[0].template[0].spec[0].automount_service_account_token && kubernetes_deployment_v1.risk.spec[0].template[0].spec[0].container[0].security_context[0].read_only_root_filesystem && !kubernetes_deployment_v1.risk.spec[0].template[0].spec[0].container[0].security_context[0].allow_privilege_escalation
    error_message = "The demo must retain the non-root, read-only, unprivileged runtime."
  }
}

run "reject_mutable_image" {
  command = plan
  variables {
    image_uri = "123456789012.dkr.ecr.us-east-1.amazonaws.com/clinical-trial-site-risk-monitor-dev-risk-service:latest"
  }
  expect_failures = [var.image_uri]
}
