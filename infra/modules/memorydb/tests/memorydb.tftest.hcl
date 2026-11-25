mock_provider "aws" {}

mock_provider "random" {
  mock_resource "random_password" {
    defaults = { result = "mock-bootstrap-password-0000000000000000000000000000000000000000" }
  }
}

variables {
  name_prefix        = "pay"
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

run "hyperswitch_password_users_with_cell_prefix" {
  command = apply

  variables {
    user_name_prefix = "cell-0-"
    users            = { ops = "on ~* +@read" }
    password_users = {
      router    = "on ~* &* +@all -@admin -@dangerous"
      drainer   = "on ~* &* +@all -@admin -@dangerous"
      scheduler = "on ~* &* +@all -@admin -@dangerous"
    }
  }

  assert {
    condition = alltrue([for k in ["router", "drainer", "scheduler"] :
    aws_memorydb_user.this[k].authentication_mode[0].type == "password" && aws_memorydb_user.this[k].user_name == "cell-0-${k}"])
    error_message = "router, drainer and scheduler log in with a password under the cell-prefixed name"
  }

  assert {
    condition     = aws_memorydb_user.this["ops"].authentication_mode[0].type == "iam" && aws_memorydb_user.this["ops"].user_name == "cell-0-ops"
    error_message = "every other user keeps IAM authentication"
  }

  assert {
    condition     = aws_memorydb_user.this["drainer"].access_string == "on ~* &* +@all -@admin -@dangerous"
    error_message = "each service keeps its own access string"
  }

  assert {
    condition     = length(random_password.bootstrap) == 3 && output.user_names["scheduler"] == "cell-0-scheduler"
    error_message = "one throwaway first password per password user and the names are exported for the deploy side"
  }

  assert {
    condition     = length(aws_memorydb_acl.this.user_names) == 4
    error_message = "the ACL holds both kinds of users"
  }
}

run "user_cannot_be_both_iam_and_password" {
  command = plan

  variables {
    password_users = { router = "on ~* +@all" }
  }

  expect_failures = [var.password_users]
}

run "user_name_prefix_is_validated" {
  command = plan

  variables {
    user_name_prefix = "Cell_0"
  }

  expect_failures = [var.user_name_prefix]
}
