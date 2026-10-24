mock_provider "aws" {
  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::clinical-trial-site-risk-monitor-tfstate-dev-697078878651"
      id  = "clinical-trial-site-risk-monitor-tfstate-dev-697078878651"
    }
  }
}

run "secure_state_storage" {
  command = apply

  assert {
    condition     = aws_s3_bucket.state.bucket == "clinical-trial-site-risk-monitor-tfstate-dev-697078878651" && !aws_s3_bucket.state.force_destroy
    error_message = "Use the project-specific bucket name and do not allow forced emptying."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.state.block_public_acls && aws_s3_bucket_public_access_block.state.block_public_policy && aws_s3_bucket_public_access_block.state.ignore_public_acls && aws_s3_bucket_public_access_block.state.restrict_public_buckets
    error_message = "All public access protections must be enabled."
  }

  assert {
    condition     = aws_s3_bucket_versioning.state.versioning_configuration[0].status == "Enabled" && one(aws_s3_bucket_server_side_encryption_configuration.state.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    error_message = "State must be versioned and encrypted at rest."
  }

  assert {
    condition     = aws_s3_bucket_ownership_controls.state.rule[0].object_ownership == "BucketOwnerEnforced"
    error_message = "Bucket ACLs must be disabled."
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.state.policy).Statement[0].Effect == "Deny" && jsondecode(aws_s3_bucket_policy.state.policy).Statement[0].Condition.Bool["aws:SecureTransport"] == "false"
    error_message = "The bucket policy must deny unencrypted transport."
  }
}
