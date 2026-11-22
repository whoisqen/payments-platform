mock_provider "aws" {}

variables {
  region              = "eu-central-1"
  environment         = "prod"
  account_id          = "333333333333"
  repositories        = ["router", "locker", "drainer"]
  kms_key_arn         = "arn:aws:kms:eu-central-1:333333333333:key/mrk-0123456789abcdef0123456789abcdef"
  replication_regions = ["us-east-1", "us-east-2"]
  tags = {
    environment = "prod", team = "platform", owner = "platform@example.com", cost-center = "cc-100", cell = "shared"
    component   = "ecr", pci-scope = "connected", data-class = "internal", backup-tier = "silver", managed-by = "terraform", repo = "infra/modules/ecr"
  }
}

run "immutable_scanned_encrypted" {
  command = plan

  assert {
    condition     = alltrue([for r in aws_ecr_repository.this : r.image_tag_mutability == "IMMUTABLE" && r.image_scanning_configuration[0].scan_on_push && r.encryption_configuration[0].encryption_type == "KMS"])
    error_message = "immutable tags, scan on push, KMS"
  }
  assert {
    condition     = aws_ecr_repository.this["router"].name == "pay-prod-euc1-router"
    error_message = "name follows pay-<env>-<region-short>-<name>"
  }
  assert {
    condition     = length(aws_ecr_lifecycle_policy.this) == 3
    error_message = "every repository has a lifecycle policy"
  }
}

run "replicates_to_both_recovery_regions" {
  command = plan

  assert {
    condition     = length(aws_ecr_replication_configuration.this[0].replication_configuration[0].rule[0].destination) == 2
    error_message = "two destinations"
  }
  assert {
    condition     = toset([for d in aws_ecr_replication_configuration.this[0].replication_configuration[0].rule[0].destination : d.region]) == toset(["us-east-1", "us-east-2"])
    error_message = "us-east-1 and us-east-2 receive images"
  }
}

run "recovery_region_holds_only_a_template" {
  command = plan

  variables {
    region              = "us-east-1"
    repositories        = []
    kms_key_arn         = null
    replication_regions = []

    create_replica_template = true
    replica_kms_key_arn = "arn:aws:kms:us-east-1:333333333333:key/mrk-0123456789abcdef0123456789abcdef"
  }

  assert {
    condition     = length(aws_ecr_repository.this) == 0 && length(aws_ecr_replication_configuration.this) == 0 && length(aws_ecr_repository_creation_template.replica) == 1
    error_message = "template only"
  }
}

run "cannot_replicate_to_itself" {
  command = plan

  variables {
    replication_regions = ["eu-central-1"]
  }

  expect_failures = [var.replication_regions]
}
