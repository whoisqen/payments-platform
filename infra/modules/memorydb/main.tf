locals {
  name = "${var.name_prefix}-${var.env}-${var.region_short}-${var.component}"

  # Keyed by service; the MemoryDB name carries user_name_prefix because user names are unique per account and region.
  users = merge(
    { for k, v in var.users : k => { access_string = v, type = "iam" } },
    { for k, v in var.password_users : k => { access_string = v, type = "password" } },
  )
}

resource "aws_memorydb_subnet_group" "this" {
  name        = local.name
  description = "Data subnets of ${local.name}"
  subnet_ids  = var.subnet_ids

  tags = var.tags
}

# noeviction keeps payment streams safe; an eviction policy would drop unread entries.
resource "aws_memorydb_parameter_group" "this" {
  name        = local.name
  family      = var.parameter_group_family
  description = "noeviction for the payment streams of ${local.name}"

  parameter {
    name  = "maxmemory-policy"
    value = "noeviction"
  }

  tags = var.tags
}

# Throwaway first password only: MemoryDB has no write-only password argument, so the real one is set out of band
# (README, rotation) and Terraform ignores it; this value is never written to Vault.
resource "random_password" "bootstrap" {
  for_each = var.password_users

  length  = 64
  special = false
}

resource "aws_memorydb_user" "this" {
  for_each = local.users

  user_name     = "${var.user_name_prefix}${each.key}"
  access_string = each.value.access_string

  authentication_mode {
    type      = each.value.type
    passwords = each.value.type == "password" ? [random_password.bootstrap[each.key].result] : null
  }

  lifecycle {
    ignore_changes = [authentication_mode[0].passwords]
  }

  tags = var.tags
}

resource "aws_memorydb_acl" "this" {
  name       = local.name
  user_names = [for u in aws_memorydb_user.this : u.user_name]

  tags = var.tags
}

# No multi-Region cluster: D7 replicates snapshots only and rebuilds the cache from Aurora at the switch.
resource "aws_memorydb_cluster" "this" {
  name                   = local.name
  description            = "Payment state and streams of ${local.name}"
  engine                 = "redis"
  engine_version         = var.engine_version
  node_type              = var.node_type
  num_shards             = var.num_shards
  num_replicas_per_shard = var.num_replicas_per_shard
  parameter_group_name   = aws_memorydb_parameter_group.this.name
  subnet_group_name      = aws_memorydb_subnet_group.this.name
  security_group_ids     = var.security_group_ids
  acl_name               = aws_memorydb_acl.this.name
  tls_enabled            = true
  kms_key_arn            = var.kms_key_arn
  port                   = 6379

  snapshot_window            = var.snapshot_window
  snapshot_retention_limit   = var.snapshot_retention_days
  final_snapshot_name        = "${local.name}-final"
  maintenance_window         = var.maintenance_window
  auto_minor_version_upgrade = true
  sns_topic_arn              = var.sns_topic_arn

  tags = var.tags
}
