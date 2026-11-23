mock_provider "aws" {}

variables {
  env                   = "prod"
  region_short          = "euc1"
  region_name           = "eu-central-1"
  account_id            = "111111111111"
  kms_key_arn           = "arn:aws:kms:eu-central-1:111111111111:key/mrk-0007"
  subnet_ids            = ["subnet-1", "subnet-2", "subnet-3"]
  security_group_ids    = ["sg-0001"]
  master_user_arn       = "arn:aws:iam::111111111111:role/opensearch-admin"
  access_principal_arns = ["arn:aws:iam::111111111111:role/fluent-bit"]
  log_group_arn         = "arn:aws:logs:eu-central-1:111111111111:log-group:/pay/prod/opensearch"
  snapshot_bucket_arn   = "arn:aws:s3:::pay-prod-euc1-backup"
  snapshot_kms_key_arn  = "arn:aws:kms:eu-central-1:111111111111:key/mrk-0004"

  tags = {
    team          = "platform"
    owner         = "platform@example.com"
    "pci-scope"   = "connected"
    "data-class"  = "internal"
    "backup-tier" = "silver"
  }
}

run "domain_is_private_encrypted_and_three_az" {
  command = plan

  assert {
    condition = (
      aws_opensearch_domain.this.domain_name == "pay-prod-euc1-opensearch" &&
      aws_opensearch_domain.this.cluster_config[0].dedicated_master_count == 3 &&
      aws_opensearch_domain.this.cluster_config[0].instance_count == 6 &&
      aws_opensearch_domain.this.cluster_config[0].zone_awareness_config[0].availability_zone_count == 3 &&
      aws_opensearch_domain.this.cluster_config[0].warm_enabled
    )
    error_message = "3 masters, 6 data nodes, 3 AZs and UltraWarm"
  }

  assert {
    condition = (
      aws_opensearch_domain.this.encrypt_at_rest[0].enabled &&
      aws_opensearch_domain.this.node_to_node_encryption[0].enabled &&
      aws_opensearch_domain.this.domain_endpoint_options[0].enforce_https &&
      !aws_opensearch_domain.this.advanced_security_options[0].internal_user_database_enabled
    )
    error_message = "encryption everywhere and no internal user database"
  }
}

run "long_names_are_rejected" {
  command = plan

  variables {
    component = "opensearch-logs-of-the-platform"
  }

  expect_failures = [aws_opensearch_domain.this]
}

run "data_nodes_stay_even_across_azs" {
  command = plan

  variables {
    data_node_count = 5
  }

  expect_failures = [var.data_node_count]
}

run "tag_schema_is_enforced" {
  command = plan

  variables {
    tags = { team = "platform" }
  }

  expect_failures = [var.tags]
}
