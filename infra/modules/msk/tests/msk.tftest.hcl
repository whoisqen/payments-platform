mock_provider "aws" {}

variables {
  name_prefix        = "pay"
  env                = "prod"
  region_short       = "euc1"
  account_id         = "111111111111"
  kms_key_arn        = "arn:aws:kms:eu-central-1:111111111111:key/mrk-0003"
  client_subnets     = ["subnet-1", "subnet-2", "subnet-3"]
  security_group_ids = ["sg-0001"]
  log_group_name     = "/pay/prod/euc1/msk"
  sink_bucket_arn    = "arn:aws:s3:::pay-prod-euc1-event-archive"
  sink_kms_key_arn   = "arn:aws:kms:eu-central-1:111111111111:key/mrk-0004"

  tags = {
    team          = "data"
    owner         = "data@example.com"
    "pci-scope"   = "connected"
    "data-class"  = "internal"
    "backup-tier" = "none"
  }
}

run "cluster_is_durable_and_authenticated" {
  command = plan

  assert {
    condition     = aws_msk_cluster.this.number_of_broker_nodes == 9 && aws_msk_cluster.this.cluster_name == "pay-prod-euc1-msk"
    error_message = "nine brokers with the standard name"
  }

  assert {
    condition = (
      aws_msk_cluster.this.client_authentication[0].sasl[0].iam &&
      !aws_msk_cluster.this.client_authentication[0].unauthenticated &&
      aws_msk_cluster.this.encryption_info[0].encryption_in_transit[0].client_broker == "TLS" &&
      aws_msk_cluster.this.encryption_info[0].encryption_in_transit[0].in_cluster
    )
    error_message = "IAM only, TLS everywhere"
  }

  assert {
    condition = (
      strcontains(aws_msk_configuration.this.server_properties, "min.insync.replicas=2") &&
      strcontains(aws_msk_configuration.this.server_properties, "default.replication.factor=3") &&
      strcontains(aws_msk_configuration.this.server_properties, "auto.create.topics.enable=false")
    )
    error_message = "RF 3, min ISR 2, no auto-created topics"
  }
}

run "sink_writes_only_under_its_prefix" {
  command = plan

  assert {
    condition     = alltrue([for s in output.sink_bucket_policy_statements : s.Effect == "Allow"]) && output.sink_bucket_policy_statements[0].Resource[0] == "arn:aws:s3:::pay-prod-euc1-event-archive/events/*"
    error_message = "sink statements are scoped to the events prefix"
  }
}

run "broker_count_stays_even_across_azs" {
  command = plan

  variables {
    broker_count = 7
  }

  expect_failures = [var.broker_count]
}

run "tag_schema_is_enforced" {
  command = plan

  variables {
    tags = { team = "data" }
  }

  expect_failures = [var.tags]
}
