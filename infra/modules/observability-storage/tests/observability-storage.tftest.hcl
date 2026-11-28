mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::222222222222:role/mock" }
  }
}

variables {
  name_prefix              = "pay"
  region_short             = "euc1"
  cluster_name             = "pay-shared-services-euc1-central"
  kms_key_arn              = "arn:aws:kms:eu-central-1:222222222222:key/mrk-shared"
  permissions_boundary_arn = "arn:aws:iam::222222222222:policy/workload-boundary"
  tags = {
    team          = "platform"
    owner         = "platform@example.com"
    "pci-scope"   = "out-of-scope"
    "data-class"  = "internal"
    "backup-tier" = "none"
  }
}

run "names_and_encryption" {
  command = plan

  assert {
    condition     = !contains(keys(aws_s3_bucket.this), "loki") && aws_s3_bucket.this["tempo"].bucket == "pay-shared-services-euc1-tempo" && aws_s3_bucket.this["sentry"].bucket == "pay-shared-services-euc1-sentry"
    error_message = "bucket names follow pay-shared-services-<region-short>-<component>"
  }

  assert {
    condition     = alltrue([for k, e in aws_s3_bucket_server_side_encryption_configuration.this : one(e.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "aws:kms" && one(e.rule).apply_server_side_encryption_by_default[0].kms_master_key_id == var.kms_key_arn])
    error_message = "SSE-KMS with the shared key"
  }

  assert {
    condition     = alltrue([for k, v in aws_s3_bucket_versioning.this : v.versioning_configuration[0].status == "Enabled"]) && alltrue([for k, p in aws_s3_bucket_public_access_block.this : p.block_public_acls && p.block_public_policy && p.ignore_public_acls && p.restrict_public_buckets])
    error_message = "versioning on and public access blocked"
  }
}

run "lifecycle_retention" {
  command = plan

  assert {
    condition     = contains([for r in aws_s3_bucket_lifecycle_configuration.this["tempo"].rule : r.expiration[0].days], 14) && contains([for r in aws_s3_bucket_lifecycle_configuration.this["sentry"].rule : r.expiration[0].days], 90)
    error_message = "tempo 14 days, sentry 90 days"
  }
}

run "tls_only_policy" {
  command = apply

  assert {
    condition     = alltrue([for k, p in aws_s3_bucket_policy.this : strcontains(p.policy, "aws:SecureTransport") && strcontains(p.policy, "\"Effect\":\"Deny\"")])
    error_message = "every bucket denies non-TLS requests"
  }
}

run "roles_are_scoped" {
  command = apply

  assert {
    condition     = alltrue([for k, r in aws_iam_role.this : r.permissions_boundary == var.permissions_boundary_arn]) && aws_iam_role.this["tempo"].name == "pay-shared-services-euc1-tempo-pod"
    error_message = "roles carry the boundary and are named after the bucket"
  }

  assert {
    condition = alltrue([
      for k, p in aws_iam_role_policy.this : alltrue([
        for s in jsondecode(p.policy).Statement :
        !contains(s.Action, "*") && alltrue([for a in s.Action : !endswith(a, ":*")]) && !contains(s.Resource, "*")
      ])
    ])
    error_message = "no wildcard action or resource"
  }

  assert {
    condition = alltrue([
      for k, p in aws_iam_role_policy.this :
      jsondecode(p.policy).Statement[0].Resource == ["arn:aws:s3:::pay-shared-services-euc1-${k}"] &&
      jsondecode(p.policy).Statement[1].Resource == ["arn:aws:s3:::pay-shared-services-euc1-${k}/*"] &&
      jsondecode(p.policy).Statement[2].Resource == [var.kms_key_arn] &&
      contains(jsondecode(p.policy).Statement[1].Action, "s3:DeleteObject")
    ])
    error_message = "each role reaches only its own bucket and the key"
  }

  assert {
    condition     = aws_eks_pod_identity_association.this["tempo"].namespace == "monitoring" && aws_eks_pod_identity_association.this["tempo"].service_account == "tempo" && aws_eks_pod_identity_association.this["sentry"].service_account == "sentry" && aws_eks_pod_identity_association.this["sentry"].cluster_name == "pay-shared-services-euc1-central"
    error_message = "monitoring/tempo and monitoring/sentry on the central cluster"
  }
}

run "rejects_other_environment" {
  command = plan

  variables {
    environment = "prod"
  }

  expect_failures = [var.environment]
}

run "backup_bucket_has_no_age_expiry_but_keeps_the_hygiene_rules" {
  command = plan

  assert {
    condition     = length([for r in aws_s3_bucket_lifecycle_configuration.this["vmbackup"].rule : r if length(r.expiration) > 0 && r.id == "expire-objects"]) == 0
    error_message = "incremental backups must not expire by age"
  }

  assert {
    condition     = length([for r in aws_s3_bucket_lifecycle_configuration.this["vmbackup"].rule : r if r.id == "expire-objects" && length(r.abort_incomplete_multipart_upload) == 1 && length(r.noncurrent_version_expiration) == 1]) == 1
    error_message = "old versions and unfinished uploads still expire"
  }

  assert {
    condition     = output.bucket_names["vmbackup"] == "pay-shared-services-euc1-vmbackup"
    error_message = "the name the backup job addresses"
  }
}

run "unfinished_uploads_are_aborted_after_one_day" {
  command = plan

  assert {
    condition     = alltrue([for k, l in aws_s3_bucket_lifecycle_configuration.this : alltrue([for r in l.rule : r.abort_incomplete_multipart_upload[0].days_after_initiation == 1 if r.id == "expire-objects"])])
    error_message = "every bucket aborts incomplete multipart uploads after 1 day"
  }
}

run "tiering_where_it_is_cheaper" {
  command = plan

  assert {
    condition     = alltrue([for r in aws_s3_bucket_lifecycle_configuration.this["tempo"].rule : length(r.transition) == 0])
    error_message = "tempo only expires"
  }
  assert {
    condition = alltrue([for k in ["sentry", "vmbackup"] : contains(flatten([
      for r in aws_s3_bucket_lifecycle_configuration.this[k].rule : [for t in r.transition : t.storage_class]
    ]), "INTELLIGENT_TIERING")])
    error_message = "sentry and vmbackup use Intelligent-Tiering"
  }
}

run "blocks_go_to_standard_ia_when_the_retention_allows" {
  command = plan

  variables {
    buckets = {
      tempo = { retention_days = 90, namespace = "monitoring", service_account = "tempo", transition = { days = 30, storage_class = "STANDARD_IA" } }
    }
  }

  assert {
    condition = anytrue([
      for r in aws_s3_bucket_lifecycle_configuration.this["tempo"].rule :
      length(r.transition) == 1 && one(r.transition).days == 30 && one(r.transition).storage_class == "STANDARD_IA" && r.expiration[0].days == 90 if r.id == "expire-objects"
    ])
    error_message = "Standard-IA after 30 days, deleted at the retention"
  }
}

run "standard_ia_before_30_days_is_rejected" {
  command = plan

  variables {
    buckets = {
      tempo = { retention_days = 90, namespace = "monitoring", service_account = "tempo", transition = { days = 7, storage_class = "STANDARD_IA" } }
    }
  }

  expect_failures = [var.buckets]
}

run "yace_reads_cloudwatch_on_the_central_cluster" {
  command = plan

  assert {
    condition     = aws_iam_role.yace[0].name == "pay-shared-services-euc1-yace-pod" && aws_iam_role.yace[0].permissions_boundary == var.permissions_boundary_arn
    error_message = "yace role with the boundary"
  }
  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_role_policy.yace[0].policy).Statement :
      alltrue([for a in s.Action : contains(["cloudwatch:GetMetricData", "cloudwatch:GetMetricStatistics", "cloudwatch:ListMetrics", "tag:GetResources"], a)])
    ])
    error_message = "metric reads and tag discovery only"
  }
  assert {
    condition     = aws_eks_pod_identity_association.yace[0].cluster_name == var.cluster_name && aws_eks_pod_identity_association.yace[0].service_account == "yace"
    error_message = "monitoring/yace on the central cluster"
  }
}
