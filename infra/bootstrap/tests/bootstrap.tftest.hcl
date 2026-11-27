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
  name_prefix       = "pay"
  account_id        = "555555555555"
  github_repository = "example-org/payments-platform"
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

run "prod_root_gets_ci_roles_but_no_account_singletons" {
  command = plan

  assert {
    condition     = length(module.ci_roles) == 1 && length(module.boundary) == 0 && length(aws_iam_openid_connect_provider.github) == 0
    error_message = "a workload root reuses the provider and boundary of the shared-services run"
  }
}

run "shared_services_root_owns_boundary_and_oidc_provider" {
  command = plan

  variables {
    environment = "shared-services"
  }

  assert {
    condition     = aws_s3_bucket.state.bucket == "pay-shared-services-euc1-tf-state-555555555555" && module.state_key.alias_name == "alias/pay-shared-services-euc1-tf-state"
    error_message = "bucket and key of the shared-services root"
  }
  assert {
    condition     = length(module.boundary) == 1 && length(aws_iam_openid_connect_provider.github) == 1 && length(module.ci_roles) == 0
    error_message = "the shared-services run creates the boundary and the provider, the live ci-oidc-roles stack its plan role"
  }
}

run "management_root" {
  command = plan

  variables {
    environment = "management"
  }

  assert {
    condition     = aws_s3_bucket.state.bucket == "pay-management-euc1-tf-state-555555555555" && module.state_key.alias_name == "alias/pay-management-euc1-tf-state" && module.state_key_use1.alias_name == "alias/pay-management-use1-tf-state"
    error_message = "bucket and keys of the management root"
  }
  assert {
    condition     = aws_iam_role.replication.name == "pay-management-euc1-tf-state-replication" && length(module.ci_roles) == 1
    error_message = "replication role and CI roles of the management root"
  }
}

run "security_root" {
  command = plan

  variables {
    environment = "security"
  }

  assert {
    condition     = aws_s3_bucket.state.bucket == "pay-security-euc1-tf-state-555555555555" && module.state_key_use2.alias_name == "alias/pay-security-use2-tf-state"
    error_message = "bucket and replica of the security root"
  }
}

run "unknown_root_is_rejected" {
  command = plan

  variables {
    environment = "audit"
  }

  expect_failures = [var.environment]
}

run "apply_roles_cover_every_component_of_the_root" {
  command = plan

  assert {
    condition     = contains(local.components, "eks") && contains(local.components, "argocd-registration") && contains(local.components, "vpc")
    error_message = "the component list comes from infra/live/prod"
  }
  assert {
    condition     = length(module.ci_roles[0].component_apply_role_arns) == length(local.components)
    error_message = "one apply role per component"
  }
}
