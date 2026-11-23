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
    condition     = aws_s3_bucket.this["loki"].bucket == "pay-shared-services-euc1-loki" && aws_s3_bucket.this["tempo"].bucket == "pay-shared-services-euc1-tempo" && aws_s3_bucket.this["sentry"].bucket == "pay-shared-services-euc1-sentry"
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
    condition     = contains([for r in aws_s3_bucket_lifecycle_configuration.this["loki"].rule : r.expiration[0].days], 30)
    error_message = "loki expires after 30 days"
  }

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
    condition     = alltrue([for k, r in aws_iam_role.this : r.permissions_boundary == var.permissions_boundary_arn]) && aws_iam_role.this["loki"].name == "pay-shared-services-euc1-loki-pod"
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
    condition     = aws_eks_pod_identity_association.this["loki"].namespace == "monitoring" && aws_eks_pod_identity_association.this["loki"].service_account == "loki" && aws_eks_pod_identity_association.this["tempo"].service_account == "tempo" && aws_eks_pod_identity_association.this["sentry"].service_account == "sentry" && aws_eks_pod_identity_association.this["sentry"].cluster_name == "pay-shared-services-euc1-central"
    error_message = "monitoring/loki, monitoring/tempo and monitoring/sentry on the central cluster"
  }
}

run "rejects_other_environment" {
  command = plan

  variables {
    environment = "prod"
  }

  expect_failures = [var.environment]
}
