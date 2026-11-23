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
    replica_kms_key_arn     = "arn:aws:kms:us-east-1:333333333333:key/mrk-0123456789abcdef0123456789abcdef"
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

run "retention_protects_promoted_images_and_signatures" {
  command = plan

  assert {
    condition     = [for r in jsondecode(aws_ecr_lifecycle_policy.this["router"].policy).rules : r.rulePriority] == [1, 2, 3, 4, 5, 10, 11]
    error_message = "promotion and signature rules come before the build rule, so a lower rule cannot expire what a higher one keeps"
  }
  assert {
    condition     = [for r in jsondecode(aws_ecr_lifecycle_policy.this["router"].policy).rules : try(r.selection.tagPrefixList[0], "")] == ["v", "prod-", "stage-", "dev-", "sha256-", "", ""]
    error_message = "release, prod, stage, dev and cosign artifact tags have a rule each"
  }
  assert {
    condition     = jsondecode(aws_ecr_lifecycle_policy.this["router"].policy).rules[1].selection.countNumber == 50 && jsondecode(aws_ecr_lifecycle_policy.this["router"].policy).rules[5].selection.countNumber == 100
    error_message = "prod keeps 50 images and unpromoted builds keep the latest 100 by default"
  }
  assert {
    condition     = length([for r in jsondecode(aws_ecr_lifecycle_policy.this["router"].policy).rules : r if r.selection.tagStatus == "untagged"]) == 1
    error_message = "ECR allows one rule that selects untagged images"
  }
}

run "retention_values_are_validated" {
  command = plan

  variables {
    retention = { releases = 0, prod = 50, stage = 20, dev = 10, signatures = 800, builds = 100, untagged_days = 3 }
  }

  expect_failures = [var.retention]
}

run "cache_repositories_are_mutable_and_expire_when_unused" {
  command = plan

  variables {
    cache_repositories = ["router"]
  }

  assert {
    condition     = aws_ecr_repository.cache["router"].image_tag_mutability == "MUTABLE" && aws_ecr_repository.cache["router"].name == "pay-prod-euc1-cache-router"
    error_message = "the buildx cache repository is mutable"
  }
  assert {
    condition     = jsondecode(aws_ecr_lifecycle_policy.cache["router"].policy).rules[0].selection.countType == "sinceImagePulled"
    error_message = "unused cache expires"
  }
}

run "pull_through_cache_rules_and_templates" {
  command = plan

  variables {
    pull_through_cache = {
      "ecr-public" = { upstream_registry_url = "public.ecr.aws" }
      "quay"       = { upstream_registry_url = "quay.io" }
    }
  }

  assert {
    condition     = length(aws_ecr_pull_through_cache_rule.this) == 2 && aws_ecr_pull_through_cache_rule.this["quay"].upstream_registry_url == "quay.io"
    error_message = "one rule per upstream registry"
  }
  assert {
    condition     = alltrue([for t in aws_ecr_repository_creation_template.pull_through : contains(t.applied_for, "PULL_THROUGH_CACHE") && t.image_tag_mutability == "MUTABLE"])
    error_message = "pulled-through repositories are created mutable with the disposable lifecycle"
  }
}
