mock_provider "aws" {}
mock_provider "aws" {
  alias = "use1"
}

override_resource {
  target          = aws_s3_bucket.state
  override_during = plan
  values          = { arn = "arn:aws:s3:::pay-prod-euc1-tf-state-555555555555", id = "pay-prod-euc1-tf-state-555555555555" }
}

override_resource {
  target          = module.replica_use1.aws_s3_bucket.this
  override_during = plan
  values          = { arn = "arn:aws:s3:::pay-prod-use1-tf-state-555555555555", id = "pay-prod-use1-tf-state-555555555555" }
}

variables {
  name_prefix              = "pay"
  account_id               = "555555555555"
  github_repository        = "example-org/payments-platform"
  permissions_boundary_arn = "arn:aws:iam::555555555555:policy/workload-boundary"
  tags = {
    environment = "prod", team = "platform", owner = "platform@example.com", cost-center = "cc-100", cell = "shared"
    component   = "tf-state", pci-scope = "connected", data-class = "internal", backup-tier = "gold", managed-by = "terraform", repo = "infra/bootstrap"
  }
}

run "state_bucket_is_protected" {
  command = plan

  assert {
    condition     = aws_s3_bucket.state.bucket == "pay-prod-euc1-tf-state-555555555555" && aws_s3_bucket.state.object_lock_enabled
    error_message = "bucket name and Object Lock"
  }
  assert {
    condition     = aws_s3_bucket_versioning.state.versioning_configuration[0].status == "Enabled"
    error_message = "versioning on"
  }
  assert {
    condition     = aws_s3_bucket_object_lock_configuration.state.rule[0].default_retention[0].mode == "GOVERNANCE" && aws_s3_bucket_object_lock_configuration.state.rule[0].default_retention[0].days == 365
    error_message = "governance lock for one year"
  }
  assert {
    condition     = aws_s3_bucket_public_access_block.state.block_public_policy && aws_s3_bucket_public_access_block.state.ignore_public_acls
    error_message = "public access blocked"
  }
}

run "replicated_with_rtc_to_the_recovery_region" {
  command = plan

  assert {
    condition     = length(aws_s3_bucket_replication_configuration.state.rule) == 1
    error_message = "one replication rule, to us-east-1"
  }
  assert {
    condition     = alltrue([for r in aws_s3_bucket_replication_configuration.state.rule : r.destination[0].replication_time[0].time[0].minutes == 15 && r.status == "Enabled"])
    error_message = "RTC of 15 minutes, enabled by default"
  }
}

run "failback_holds_replication" {
  command = plan

  variables {
    replication_enabled = false
  }

  assert {
    condition     = alltrue([for r in aws_s3_bucket_replication_configuration.state.rule : r.status == "Disabled"])
    error_message = "replication disabled during a failback"
  }
}

run "dr_role_reads_and_writes_the_environment_prefix" {
  command = plan

  variables {
    dr_apply_role_arns = ["arn:aws:iam::444444444444:role/pay-prod-glob-dr-apply"]
  }

  assert {
    condition     = one([for s in jsondecode(aws_s3_bucket_policy.state.policy).Statement : s.Resource if s.Sid == "DrStateReadWrite"]) == "arn:aws:s3:::pay-prod-euc1-tf-state-555555555555/prod/*"
    error_message = "working bucket: prod/ only"
  }
  assert {
    condition     = module.replica_use1.bucket_name == "pay-prod-use1-tf-state-555555555555" && module.replica_use1.bucket_arn == "arn:aws:s3:::pay-prod-use1-tf-state-555555555555"
    error_message = "replica follows the name that infra/live/terragrunt.hcl builds for PAY_STATE_REGION=us-east-1"
  }
}

run "no_dr_grant_by_default" {
  command = plan

  assert {
    condition     = length(jsondecode(aws_s3_bucket_policy.state.policy).Statement) == 2
    error_message = "only the two denies"
  }
}

run "key_is_multi_region_with_a_replica" {
  command = plan

  assert {
    condition     = module.state_key.alias_name == "alias/pay-prod-euc1-tf-state" && module.state_key_use1.alias_name == "alias/pay-prod-use1-tf-state"
    error_message = "primary and its us-east-1 replica"
  }
}

run "replication_role_name" {
  command = plan

  assert {
    condition     = aws_iam_role.replication.name == "pay-prod-euc1-tf-state-replication"
    error_message = "replication role follows the naming rule"
  }
}
