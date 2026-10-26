mock_provider "aws" {}

variables {
  repository_name = "clinical-trial-site-risk-monitor-dev-risk-service"
  tags = {
    Project     = "clinical-trial-site-risk-monitor"
    Environment = "dev"
    ManagedBy   = "Terraform-Terragrunt"
  }
}

run "private_image_storage" {
  command = plan

  assert {
    condition     = aws_ecr_repository.this.name == var.repository_name && aws_ecr_repository.this.tags["Name"] == var.repository_name && aws_ecr_repository.this.tags["Project"] == var.tags["Project"] && aws_ecr_repository.this.tags["Environment"] == "dev"
    error_message = "The repository must identify its project, environment, and purpose."
  }

  assert {
    condition     = aws_ecr_repository.this.image_tag_mutability == "IMMUTABLE" && aws_ecr_repository.this.image_scanning_configuration[0].scan_on_push
    error_message = "Scan pushed images and prevent existing image tags from being overwritten."
  }

  assert {
    condition     = aws_ecr_repository.this.encryption_configuration[0].encryption_type == "AES256" && !aws_ecr_repository.this.force_delete
    error_message = "Encrypt stored images and refuse forced deletion of a populated repository."
  }
}

run "reject_invalid_name" {
  command = plan
  variables {
    repository_name = "Invalid Repository Name"
  }
  expect_failures = [var.repository_name]
}
