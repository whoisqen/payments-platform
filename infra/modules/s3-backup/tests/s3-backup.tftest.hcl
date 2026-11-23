mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111111111111:role/mock" }
  }
}

variables {
  name_prefix  = "pay"
  env          = "prod"
  region_short = "euc1"
  region_name  = "eu-central-1"
  kms_key_arn  = "arn:aws:kms:eu-central-1:111111111111:key/mrk-0004"

  recovery_regions = {
    "us-east-1" = { short = "use1", kms_key_arn = "arn:aws:kms:us-east-1:111111111111:key/mrk-0004" }
    "us-east-2" = { short = "use2", kms_key_arn = "arn:aws:kms:us-east-2:111111111111:key/mrk-0004" }
  }

  tags = {
    team          = "platform"
    owner         = "platform@example.com"
    "pci-scope"   = "cde"
    "data-class"  = "internal"
    "backup-tier" = "gold"
  }
}

run "working_region_replicates_with_rtc" {
  command = apply

  assert {
    condition     = length(aws_s3_bucket.this) == 3 && alltrue([for b in aws_s3_bucket.this : b.object_lock_enabled])
    error_message = "source plus two destinations, all with Object Lock"
  }

  assert {
    condition     = aws_s3_bucket.this["us-east-1"].bucket == "pay-prod-use1-backup" && aws_s3_bucket.this["eu-central-1"].bucket == "pay-prod-euc1-backup"
    error_message = "bucket names follow pay-<env>-<region-short>-<component>"
  }

  assert {
    condition = (
      length(aws_s3_bucket_replication_configuration.this[0].rule) == 2 &&
      alltrue([for r in aws_s3_bucket_replication_configuration.this[0].rule :
        r.destination[0].replication_time[0].time[0].minutes == 15 &&
        r.destination[0].metrics[0].event_threshold[0].minutes == 15 &&
      r.destination[0].replication_time[0].status == "Enabled"])
    )
    error_message = "each destination needs Replication Time Control at 15 minutes"
  }

  assert {
    condition     = alltrue([for r in aws_s3_bucket_replication_configuration.this[0].rule : r.priority >= 1]) && length(distinct([for r in aws_s3_bucket_replication_configuration.this[0].rule : r.priority])) == 2
    error_message = "rules need distinct priorities"
  }

  assert {
    condition     = alltrue([for c in aws_s3_bucket_object_lock_configuration.this : c.rule[0].default_retention[0].mode == "COMPLIANCE"])
    error_message = "every copy is locked in compliance mode"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.replication_latency) == 2
    error_message = "one latency alarm per destination"
  }
}

run "lifecycle_tiers_at_7_and_14_days" {
  command = apply

  assert {
    condition = alltrue([
      for r in aws_s3_bucket_lifecycle_configuration.this["eu-central-1"].rule :
      r.id == "monthly-archive" || r.id == "abort-multipart" ||
      (one([for t in r.transition : t.days if t.storage_class == "GLACIER_IR"]) == 7 && one([for t in r.transition : t.days if t.storage_class == "GLACIER"]) == 14)
    ])
    error_message = "colder tiers at 7 and 14 days"
  }

  assert {
    condition     = anytrue([for r in aws_s3_bucket_lifecycle_configuration.this["eu-central-1"].rule : r.id == "monthly-archive" && r.expiration[0].days == 2555 && one([for t in r.transition : t.storage_class]) == "DEEP_ARCHIVE"])
    error_message = "monthly archive lives 7 years in the coldest tier"
  }
}

run "recovery_role_makes_only_a_locked_bucket" {
  command = apply

  variables {
    region_role      = "recovery"
    region_name      = "us-east-1"
    region_short     = "use1"
    recovery_regions = {}
  }

  assert {
    condition     = length(aws_s3_bucket.this) == 1 && length(aws_s3_bucket_replication_configuration.this) == 0 && aws_s3_bucket.this["us-east-1"].object_lock_enabled
    error_message = "a recovery stack holds one locked bucket and replicates nothing"
  }
}

run "extra_policy_statements_reach_the_source_bucket" {
  command = apply

  variables {
    bucket_policy_statements = [{ Sid = "MskS3SinkWrite", Effect = "Allow", Principal = { AWS = "arn:aws:iam::111111111111:role/sink" }, Action = ["s3:PutObject"], Resource = ["arn:aws:s3:::pay-prod-euc1-backup/events/*"] }]
  }

  assert {
    condition     = strcontains(aws_s3_bucket_policy.this["eu-central-1"].policy, "MskS3SinkWrite") && !strcontains(aws_s3_bucket_policy.this["us-east-1"].policy, "MskS3SinkWrite") && strcontains(aws_s3_bucket_policy.this["us-east-1"].policy, "aws:SecureTransport")
    error_message = "extra statements only on the source bucket, TLS deny everywhere"
  }
}

run "tag_schema_is_enforced" {
  command = plan

  variables {
    tags = { team = "platform" }
  }

  expect_failures = [var.tags]
}
