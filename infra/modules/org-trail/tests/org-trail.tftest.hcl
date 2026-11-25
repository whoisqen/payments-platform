mock_provider "aws" {
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:eu-central-1:666666666666:key/00000000-0000-0000-0000-000000000002" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:eu-central-1:666666666666:log-group:/aws/cloudtrail/pay-management-euc1-org-trail" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::666666666666:role/pay-management-euc1-org-trail-cloudwatch" }
  }
}

variables {
  region_short           = "euc1"
  region_name            = "eu-central-1"
  account_id             = "666666666666"
  s3_bucket_name         = "pay-security-euc1-log-archive"
  s3_kms_key_arn         = "arn:aws:kms:eu-central-1:555555555555:key/00000000-0000-0000-0000-000000000001"
  cde_s3_bucket_prefixes = ["pay-prod-", "pay-cde-"]

  tags = {
    team          = "security"
    owner         = "security@example.com"
    "pci-scope"   = "connected"
    "data-class"  = "internal"
    "backup-tier" = "none"
  }
}

run "trail_covers_the_organization" {
  command = apply

  assert {
    condition = (
      aws_cloudtrail.this.is_organization_trail &&
      aws_cloudtrail.this.is_multi_region_trail &&
      aws_cloudtrail.this.enable_log_file_validation &&
      aws_cloudtrail.this.include_global_service_events
    )
    error_message = "organization, multi-region trail with log file validation"
  }

  assert {
    condition     = aws_cloudtrail.this.name == "pay-management-euc1-org-trail" && aws_cloudtrail.this.kms_key_id == var.s3_kms_key_arn && aws_cloudtrail.this.s3_key_prefix == "cloudtrail"
    error_message = "name, archive key and prefix match what log-archive expects"
  }

  assert {
    condition     = aws_cloudtrail.this.cloud_watch_logs_group_arn == "${aws_cloudwatch_log_group.this.arn}:*" && aws_cloudwatch_log_group.this.kms_key_id == aws_kms_key.logs.arn
    error_message = "the trail feeds an encrypted log group"
  }
}

run "cde_buckets_get_data_events" {
  command = plan

  assert {
    condition = length([
      for s in aws_cloudtrail.this.advanced_event_selector : s
      if anytrue([for f in s.field_selector : f.field == "resources.ARN" && toset(f.starts_with) == toset(["arn:aws:s3:::pay-prod-", "arn:aws:s3:::pay-cde-"])])
    ]) == 1
    error_message = "S3 data events are selected for the CDE bucket prefixes"
  }

  assert {
    condition     = length(aws_cloudtrail.this.advanced_event_selector) == 2
    error_message = "management events plus CDE S3 data events"
  }

  assert {
    condition     = local.logs_key_policy.Statement[1].Condition.ArnEquals["kms:EncryptionContext:aws:logs:arn"] == local.log_group_arn
    error_message = "the log group key is scoped to its log group"
  }
}

run "no_cde_prefix_fails" {
  command = plan

  variables {
    cde_s3_bucket_prefixes = []
  }

  expect_failures = [var.cde_s3_bucket_prefixes]
}
