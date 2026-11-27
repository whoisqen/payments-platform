mock_provider "aws" {}

variables {
  name_prefix  = "pay"
  env          = "prod"
  region_short = "euc1"
  kms_key_arn  = "arn:aws:kms:eu-central-1:111111111111:key/mrk-0006"

  secrets = {
    "db-master" = { description = "Aurora master credentials reference" }
    "psp-keys"  = { description = "PSP API keys" }
  }

  recovery_regions = {
    "us-east-1" = { kms_key_arn = "arn:aws:kms:us-east-1:111111111111:key/mrk-0006" }
  }

  tags = {
    team          = "security"
    owner         = "security@example.com"
    "pci-scope"   = "cde"
    "data-class"  = "card-data"
    "backup-tier" = "gold"
  }
}

run "every_secret_is_replicated_to_both_regions" {
  command = plan

  assert {
    condition     = aws_secretsmanager_secret.this["db-master"].name == "pay-prod-euc1-db-master"
    error_message = "secret name follows pay-<env>-<region-short>-<key>"
  }

  assert {
    condition = alltrue([
      for s in aws_secretsmanager_secret.this :
      toset([for r in s.replica : r.region]) == toset(["us-east-1"])
    ])
    error_message = "each secret needs a replica in both recovery regions"
  }

  assert {
    condition     = alltrue([for s in aws_secretsmanager_secret.this : alltrue([for r in s.replica : strcontains(r.kms_key_id, r.region)])])
    error_message = "each replica uses the key of its own region"
  }
}

run "tag_schema_is_enforced" {
  command = plan

  variables {
    tags = { team = "security" }
  }

  expect_failures = [var.tags]
}
