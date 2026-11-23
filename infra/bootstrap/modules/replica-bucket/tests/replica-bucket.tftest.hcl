mock_provider "aws" {}

variables {
  name_prefix = "pay"
  region      = "us-east-1"
  environment = "prod"
  account_id  = "555555555555"
  kms_key_arn = "arn:aws:kms:us-east-1:555555555555:key/mrk-0123456789abcdef0123456789abcdef"
  tags        = { team = "platform" }
}

run "locked_versioned_encrypted" {
  command = plan

  assert {
    condition     = aws_s3_bucket.this.bucket == "pay-prod-use1-tf-state-555555555555" && aws_s3_bucket.this.object_lock_enabled
    error_message = "named per convention with Object Lock"
  }
  assert {
    condition     = aws_s3_bucket_object_lock_configuration.this.rule[0].default_retention[0].mode == "GOVERNANCE"
    error_message = "governance mode"
  }
  assert {
    condition     = alltrue([for r in aws_s3_bucket_server_side_encryption_configuration.this.rule : alltrue([for d in r.apply_server_side_encryption_by_default : d.sse_algorithm == "aws:kms"])])
    error_message = "SSE-KMS"
  }
  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_acls && aws_s3_bucket_public_access_block.this.restrict_public_buckets
    error_message = "public access blocked"
  }
}

run "wrong_region_rejected" {
  command = plan

  variables {
    region = "eu-central-1"
  }

  expect_failures = [var.region]
}
