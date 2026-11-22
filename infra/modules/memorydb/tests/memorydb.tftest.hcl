mock_provider "aws" {}

variables {
  env                = "prod"
  region_short       = "euc1"
  component          = "memorydb-cell-0"
  kms_key_arn        = "arn:aws:kms:eu-central-1:111111111111:key/mrk-0001"
  subnet_ids         = ["subnet-1", "subnet-2", "subnet-3"]
  security_group_ids = ["sg-0001"]
  users              = { router = "on ~* +@all", drainer = "on ~* +@all" }

  tags = {
    team          = "payments-core"
    owner         = "payments-core@example.com"
    "pci-scope"   = "cde"
    "data-class"  = "card-data"
    "backup-tier" = "gold"
  }
}

run "cluster_shape_and_snapshots" {
  command = plan

  assert {
    condition     = aws_memorydb_cluster.this.name == "pay-prod-euc1-memorydb-cell-0" && aws_memorydb_cluster.this.num_shards == 2 && aws_memorydb_cluster.this.num_replicas_per_shard == 2
    error_message = "two shards with two replicas each and the standard name"
  }

  assert {
    condition     = aws_memorydb_cluster.this.tls_enabled && aws_memorydb_cluster.this.snapshot_retention_limit == 35
    error_message = "TLS on and 35-day snapshots"
  }

  assert {
    condition     = length(aws_memorydb_user.this) == 2 && alltrue([for u in aws_memorydb_user.this : u.authentication_mode[0].type == "iam"])
    error_message = "users authenticate with IAM"
  }
}

run "replica_count_is_pinned_to_three_azs" {
  command = plan

  variables {
    num_replicas_per_shard = 1
  }

  expect_failures = [var.num_replicas_per_shard]
}

run "tag_schema_is_enforced" {
  command = plan

  variables {
    tags = { team = "payments-core" }
  }

  expect_failures = [var.tags]
}
