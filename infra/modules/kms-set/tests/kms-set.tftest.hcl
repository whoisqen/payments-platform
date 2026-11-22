mock_provider "aws" {}

variables {
  account_id  = "111111111111"
  region      = "eu-central-1"
  environment = "dev"
  keys = {
    ebs-nodes = {}
    locker    = {}
    logs      = { service_principals = ["logs.eu-central-1.amazonaws.com"] }
  }
  tags = {
    team = "platform", owner = "platform@example.com", pci-scope = "cde", data-class = "card-data", backup-tier = "gold"
  }
}

run "primaries_are_named_by_purpose" {
  command = plan

  assert {
    condition     = length(module.key) == 3
    error_message = "one key per purpose"
  }
  assert {
    condition     = module.key["ebs-nodes"].alias_name == "alias/pay-dev-euc1-ebs-nodes"
    error_message = "alias follows pay-<env>-<region-short>-<purpose>"
  }
}

run "replicas_need_every_primary" {
  command = plan

  variables {
    region           = "us-east-1"
    is_replica       = true
    primary_key_arns = { ebs-nodes = "arn:aws:kms:eu-central-1:111111111111:key/mrk-aaa" }
  }

  expect_failures = [var.primary_key_arns]
}

run "replica_set_mirrors_the_primary_set" {
  command = plan

  variables {
    region     = "us-east-1"
    is_replica = true
    primary_key_arns = {
      ebs-nodes = "arn:aws:kms:eu-central-1:111111111111:key/mrk-aaa"
      locker    = "arn:aws:kms:eu-central-1:111111111111:key/mrk-bbb"
      logs      = "arn:aws:kms:eu-central-1:111111111111:key/mrk-ccc"
    }
  }

  assert {
    condition     = module.key["locker"].alias_name == "alias/pay-dev-use1-locker"
    error_message = "replica alias carries the recovery region"
  }
}
