mock_provider "aws" {}
mock_provider "aws" {
  alias = "use1"
}
mock_provider "aws" {
  alias = "use2"
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

run "replicated_with_rtc_to_both_recovery_regions" {
  command = plan

  assert {
    condition     = length(aws_s3_bucket_replication_configuration.state.rule) == 2
    error_message = "two replication rules"
  }
  assert {
    condition     = alltrue([for r in aws_s3_bucket_replication_configuration.state.rule : r.destination[0].replication_time[0].time[0].minutes == 15])
    error_message = "RTC of 15 minutes"
  }
  assert {
    condition     = toset([for r in aws_s3_bucket_replication_configuration.state.rule : r.priority]) == toset([1, 2])
    error_message = "one rule per recovery region"
  }
}

run "key_is_multi_region_with_two_replicas" {
  command = plan

  assert {
    condition     = module.state_key.alias_name == "alias/pay-prod-euc1-tf-state" && module.state_key_use1.alias_name == "alias/pay-prod-use1-tf-state" && module.state_key_use2.alias_name == "alias/pay-prod-use2-tf-state"
    error_message = "primary and two replicas"
  }
}

run "replication_role_name" {
  command = plan

  assert {
    condition     = aws_iam_role.replication.name == "pay-prod-euc1-tf-state-replication"
    error_message = "replication role follows the naming rule"
  }
}
