mock_provider "aws" {}

variables {
  env                      = "prod"
  region_short             = "euc1"
  region_name              = "eu-central-1"
  primary_region           = "eu-central-1"
  component                = "aurora-cell-0"
  kms_key_arn              = "arn:aws:kms:eu-central-1:111111111111:key/mrk-0001"
  db_subnet_group_name     = "pay-prod-euc1-data"
  security_group_ids       = ["sg-0001"]
  availability_zones       = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
  writer_az                = "eu-central-1b"
  proxy_subnet_ids         = ["subnet-1", "subnet-2", "subnet-3"]
  proxy_security_group_ids = ["sg-0002"]

  tags = {
    team          = "payments-core"
    owner         = "payments-core@example.com"
    "pci-scope"   = "cde"
    "data-class"  = "card-data"
    "backup-tier" = "gold"
  }

  recovery_regions = {
    "us-east-1" = {
      short              = "use1"
      kms_key_arn        = "arn:aws:kms:us-east-1:111111111111:key/mrk-0001"
      db_subnet_group    = "pay-prod-use1-data"
      security_group_ids = ["sg-1001"]
    }
    "us-east-2" = {
      short              = "use2"
      kms_key_arn        = "arn:aws:kms:us-east-2:111111111111:key/mrk-0001"
      db_subnet_group    = "pay-prod-use2-data"
      security_group_ids = ["sg-2001"]
    }
  }
}

run "working_region_cluster" {
  command = plan

  assert {
    condition     = aws_rds_cluster.primary[0].cluster_identifier == "pay-prod-euc1-aurora-cell-0"
    error_message = "cluster name must follow pay-<env>-<region-short>-<component>"
  }

  assert {
    condition     = aws_rds_cluster.primary[0].backup_retention_period == 35 && aws_rds_cluster.primary[0].storage_encrypted
    error_message = "writer cluster needs 35 days of PITR and encryption"
  }

  assert {
    condition     = aws_rds_cluster_instance.writer[0].availability_zone == "eu-central-1b" && aws_rds_cluster_instance.reader[0].availability_zone == "eu-central-1a"
    error_message = "writer must sit in writer_az and the reader in another AZ"
  }

  assert {
    condition = alltrue([
      anytrue([for p in aws_rds_cluster_parameter_group.this["eu-central-1"].parameter : p.name == "rds.force_ssl" && p.value == "1"]),
      anytrue([for p in aws_rds_cluster_parameter_group.this["eu-central-1"].parameter : p.name == "ssl_min_protocol_version" && p.value == "TLSv1.3"]),
      anytrue([for p in aws_rds_cluster_parameter_group.this["eu-central-1"].parameter : p.name == "shared_preload_libraries" && strcontains(p.value, "pg_stat_statements")]),
    ])
    error_message = "parameter group must force TLS 1.3 and load pg_stat_statements"
  }

  assert {
    condition     = !anytrue([for p in aws_rds_cluster_parameter_group.this["us-east-1"].parameter : p.name == "rds.global_db_rpo"])
    error_message = "managed RPO must stay off because it pauses commits in Frankfurt"
  }

  assert {
    condition     = aws_db_proxy.this[0].require_tls && aws_db_proxy_default_target_group.this[0].connection_pool_config[0].max_connections_percent == 80
    error_message = "proxy needs TLS and an 80% connection ceiling"
  }
}

run "headless_secondaries_and_lag_alarm" {
  command = plan

  assert {
    condition     = length(aws_rds_cluster.secondary) == 2 && length(aws_rds_cluster_instance.recovery) == 0
    error_message = "both recovery regions get a storage-only cluster and no instance"
  }

  assert {
    condition     = alltrue([for a in aws_cloudwatch_metric_alarm.global_lag : a.threshold == 5000 && a.metric_name == "AuroraGlobalDBReplicationLag"])
    error_message = "lag alarm fires above 5 s"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.global_lag["us-east-2"].region == "us-east-2"
    error_message = "the lag alarm lives in the secondary region"
  }
}

run "recovery_role_joins_global_cluster" {
  command = plan

  variables {
    region_role               = "recovery"
    region_name               = "us-east-1"
    region_short              = "use1"
    global_cluster_identifier = "pay-prod-euc1-aurora-cell-0"
    recovery_regions          = {}
    kms_key_arn               = "arn:aws:kms:us-east-1:111111111111:key/mrk-0001"
    availability_zones        = ["us-east-1a", "us-east-1b", "us-east-1c"]
  }

  assert {
    condition     = length(aws_rds_global_cluster.this) == 0 && length(aws_rds_cluster.primary) == 0 && length(aws_db_proxy.this) == 0
    error_message = "a recovery stack creates no writer and no proxy until the switch"
  }

  assert {
    condition     = length(aws_rds_cluster.secondary) == 1 && length(aws_rds_cluster_instance.recovery) == 0
    error_message = "a recovery stack holds one headless cluster"
  }
}

run "switch_creates_instances_and_proxy" {
  command = plan

  variables {
    region_role               = "recovery"
    region_name               = "us-east-1"
    region_short              = "use1"
    global_cluster_identifier = "pay-prod-euc1-aurora-cell-0"
    recovery_regions          = {}
    recovery_instance_count   = 2
    proxy_secret_arn          = "arn:aws:secretsmanager:us-east-1:111111111111:secret:db-0001"
    availability_zones        = ["us-east-1a", "us-east-1b", "us-east-1c"]
  }

  assert {
    condition     = length(aws_rds_cluster_instance.recovery) == 2 && length(aws_db_proxy.this) == 1
    error_message = "the switch adds instances and the proxy"
  }
}

run "tag_schema_is_enforced" {
  command = plan

  variables {
    tags = {
      team         = "payments-core"
      owner        = "payments-core@example.com"
      "pci-scope"  = "cde"
      "data-class" = "card-data"
    }
  }

  expect_failures = [var.tags]
}

run "backup_tier_none_is_rejected" {
  command = plan

  variables {
    tags = {
      team          = "payments-core"
      owner         = "payments-core@example.com"
      "pci-scope"   = "cde"
      "data-class"  = "card-data"
      "backup-tier" = "none"
    }
  }

  expect_failures = [var.tags]
}

run "region_role_is_validated" {
  command = plan

  variables {
    region_role = "standby"
  }

  expect_failures = [var.region_role]
}

run "standby_readers_without_proxy_secret" {
  command = plan

  variables {
    region_role               = "recovery"
    region_name               = "us-east-1"
    region_short              = "use1"
    global_cluster_identifier = "pay-stage-euc1-aurora-cell-0"
    recovery_regions          = {}
    recovery_instance_count   = 1
    recovery_instance_class   = "db.r7g.large"
    availability_zones        = ["us-east-1a", "us-east-1b", "us-east-1c"]
  }

  assert {
    condition     = length(aws_rds_cluster_instance.recovery) == 1 && length(aws_db_proxy.this) == 0
    error_message = "standby readers run without a proxy when no secret is given"
  }

  assert {
    condition     = aws_rds_cluster_instance.recovery[0].instance_class == "db.r7g.large"
    error_message = "standby readers use recovery_instance_class"
  }
}

