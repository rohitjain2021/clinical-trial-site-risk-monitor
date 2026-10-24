# Bootstrap state stays local because the bucket must exist before it can store state.
terraform {
  required_version = ">= 1.10.0, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region              = "us-east-1"
  allowed_account_ids = ["697078878651"]
}

locals {
  bucket_name = "clinical-trial-site-risk-monitor-tfstate-dev-697078878651"
  tags = {
    Project     = "clinical-trial-site-risk-monitor"
    Environment = "dev"
    Purpose     = "Terraform remote state and locking"
    ManagedBy   = "Terraform-Terragrunt"
  }
}

# State is durable infrastructure: Terraform must not empty or destroy this bucket.
resource "aws_s3_bucket" "state" {
  bucket        = local.bucket_name
  force_destroy = false
  tags          = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

# Preserve historical state versions for recovery from accidental overwrites.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Disable ACLs so access is controlled by IAM and bucket policies.
resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# This is a deny-only policy. It grants no principal access to state.
resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

output "bucket_name" {
  description = "Project-specific S3 bucket for development Terraform state and lock objects."
  value       = aws_s3_bucket.state.id
}

output "bucket_arn" {
  description = "Bucket ARN for scoping the future CI deployment role's state permissions."
  value       = aws_s3_bucket.state.arn
}
