mock_provider "aws" {}

override_resource {
  target          = aws_s3_bucket.this
  override_during = plan
  values          = { arn = "arn:aws:s3:::pay-prod-use1-tf-state-555555555555", id = "pay-prod-use1-tf-state-555555555555" }
}

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

run "no_writer_by_default" {
  command = plan

  assert {
    condition     = length(jsondecode(aws_s3_bucket_policy.tls_only.policy).Statement) == 2
    error_message = "only the TLS and SSE-KMS denies without writers"
  }
}

run "dr_role_writes_its_environment_prefix_only" {
  command = plan

  variables {
    writer_role_arns = ["arn:aws:iam::444444444444:role/pay-prod-glob-dr-apply"]
  }

  assert {
    condition     = one([for s in jsondecode(aws_s3_bucket_policy.tls_only.policy).Statement : s.Resource if s.Sid == "SwitchStateReadWrite"]) == "arn:aws:s3:::pay-prod-use1-tf-state-555555555555/prod/*"
    error_message = "read and write on prod/ only"
  }
  assert {
    condition     = one([for s in jsondecode(aws_s3_bucket_policy.tls_only.policy).Statement : s.Condition.StringLike["s3:prefix"] if s.Sid == "SwitchStateList"]) == ["prod/*"]
    error_message = "list limited to prod/"
  }
  assert {
    condition     = contains([for s in jsondecode(aws_s3_bucket_policy.tls_only.policy).Statement : s.Sid], "KmsEncryptedWritesOnly")
    error_message = "unencrypted writes denied"
  }
}

run "writer_must_be_a_role" {
  command = plan

  variables {
    writer_role_arns = ["*"]
  }

  expect_failures = [var.writer_role_arns]
}
