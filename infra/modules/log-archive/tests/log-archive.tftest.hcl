mock_provider "aws" {
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:eu-central-1:555555555555:key/00000000-0000-0000-0000-000000000001", key_id = "00000000-0000-0000-0000-000000000001" }
  }
  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::pay-security-euc1-log-archive" }
  }
}

variables {
  region_short          = "euc1"
  account_id            = "555555555555"
  management_account_id = "666666666666"
  organization_id       = "o-abcdefghij"
  trail_arn             = "arn:aws:cloudtrail:eu-central-1:666666666666:trail/pay-management-euc1-org-trail"
  reader_principal_arns = ["arn:aws:iam::777777777777:role/security-audit"]

  tags = {
    team          = "security"
    owner         = "security@example.com"
    "pci-scope"   = "connected"
    "data-class"  = "internal"
    "backup-tier" = "none"
  }
}

run "bucket_is_locked_encrypted_and_tiered" {
  command = apply

  assert {
    condition     = aws_s3_bucket.this.bucket == "pay-security-euc1-log-archive" && aws_s3_bucket.this.object_lock_enabled
    error_message = "bucket name follows the convention and has Object Lock"
  }

  assert {
    condition = (
      aws_s3_bucket_object_lock_configuration.this.rule[0].default_retention[0].mode == "COMPLIANCE" &&
      aws_s3_bucket_object_lock_configuration.this.rule[0].default_retention[0].days == 365
    )
    error_message = "COMPLIANCE retention of 365 days"
  }

  assert {
    condition     = one([for r in aws_s3_bucket_server_side_encryption_configuration.this.rule : one(r.apply_server_side_encryption_by_default).kms_master_key_id]) == aws_kms_key.this.arn && aws_kms_key.this.enable_key_rotation
    error_message = "SSE-KMS with a rotated key"
  }

  assert {
    condition = (
      one(aws_s3_bucket_lifecycle_configuration.this.rule[0].transition).storage_class == "GLACIER" &&
      one(aws_s3_bucket_lifecycle_configuration.this.rule[0].transition).days == 90 &&
      aws_s3_bucket_lifecycle_configuration.this.rule[0].expiration[0].days == 400
    )
    error_message = "Glacier after 90 days, expiry after 400"
  }

  assert {
    condition     = aws_s3_bucket_logging.this.target_bucket == aws_s3_bucket.access.id && aws_s3_bucket.access.object_lock_enabled != true
    error_message = "access logs go to a separate bucket without Object Lock"
  }
}

run "policy_is_tls_only_denies_delete_and_scopes_writers" {
  command = plan

  assert {
    condition     = local.bucket_policy.Statement[0].Condition.Bool["aws:SecureTransport"] == "false" && local.bucket_policy.Statement[0].Effect == "Deny"
    error_message = "insecure transport is denied"
  }

  assert {
    condition     = contains(local.bucket_policy.Statement[1].Action, "s3:DeleteObjectVersion") && contains(local.bucket_policy.Statement[1].Action, "s3:DeleteBucket") && local.bucket_policy.Statement[1].Principal == "*"
    error_message = "deletes are denied to everyone"
  }

  assert {
    condition     = !anytrue([for s in local.bucket_policy.Statement : s.Effect == "Deny" && contains(flatten([s.Action]), "s3:PutBucketPolicy")])
    error_message = "the policy never denies PutBucketPolicy, or Terraform would lock itself out"
  }

  assert {
    condition = alltrue([
      for s in local.bucket_policy.Statement : can(s.Condition.StringEquals["aws:SourceArn"]) || can(s.Condition.StringEquals["aws:SourceOrgID"])
      if s.Effect == "Allow" && can(s.Principal.Service)
    ])
    error_message = "every service principal is scoped by aws:SourceArn or aws:SourceOrgID"
  }

  assert {
    condition     = contains(local.bucket_policy.Statement[3].Resource, "arn:aws:s3:::pay-security-euc1-log-archive/cloudtrail/AWSLogs/o-abcdefghij/*")
    error_message = "the organization trail writes under cloudtrail/AWSLogs/<org-id>/"
  }

  assert {
    condition     = local.key_policy.Statement[1].Condition.StringLike["kms:EncryptionContext:aws:cloudtrail:arn"] == "arn:aws:cloudtrail:*:666666666666:trail/*"
    error_message = "the key lets the management account's trails encrypt"
  }
}

run "expiry_before_lock_end_fails" {
  command = plan

  variables {
    expiration_days = 300
  }

  expect_failures = [var.expiration_days]
}

run "lock_shorter_than_a_year_fails" {
  command = plan

  variables {
    object_lock_days = 90
  }

  expect_failures = [var.object_lock_days]
}
