locals {
  name    = "${var.name_prefix}-${var.env}-${var.region_short}-${var.component}"
  working = var.region_role == "working"

  reader_azs = [for az in var.availability_zones : az if az != var.writer_az]

  # A recovery stack holds exactly one cluster, in its own region, keyed like the working-role map.
  secondaries = local.working ? var.recovery_regions : {
    (var.region_name) = {
      short              = var.region_short
      kms_key_arn        = var.kms_key_arn
      db_subnet_group    = var.db_subnet_group_name
      security_group_ids = var.security_group_ids
    }
  }

  parameter_regions = local.working ? toset(concat([var.region_name], keys(var.recovery_regions))) : toset([var.region_name])

  cluster_parameters = [
    { name = "rds.force_ssl", value = "1", apply_method = "immediate" },
    { name = "ssl_min_protocol_version", value = "TLSv1.3", apply_method = "immediate" },
    { name = "shared_preload_libraries", value = "pg_stat_statements,pgaudit", apply_method = "pending-reboot" },
    { name = "pg_stat_statements.track", value = "all", apply_method = "immediate" },
    { name = "log_min_duration_statement", value = "250", apply_method = "immediate" },
    { name = "pgaudit.log", value = "ddl,role", apply_method = "immediate" },
  ]

  proxy_enabled    = local.working || var.recovery_instance_count > 0
  proxy_cluster_id = local.working ? aws_rds_cluster.primary[0].id : aws_rds_cluster.secondary[var.region_name].id
  proxy_secret_arn = local.working ? aws_rds_cluster.primary[0].master_user_secret[0].secret_arn : var.proxy_secret_arn
}

resource "aws_rds_cluster_parameter_group" "this" {
  for_each = local.parameter_regions

  region      = each.key
  name        = local.name
  family      = var.parameter_group_family
  description = "TLS 1.3 only, pg_stat_statements and pgaudit for ${local.name}"

  dynamic "parameter" {
    for_each = local.cluster_parameters

    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = var.tags
}

resource "aws_rds_global_cluster" "this" {
  count = local.working ? 1 : 0

  global_cluster_identifier = local.name
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = var.database_name
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection

  tags = var.tags
}

resource "aws_rds_cluster" "primary" {
  count = local.working ? 1 : 0

  cluster_identifier        = local.name
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  global_cluster_identifier = aws_rds_global_cluster.this[0].id
  database_name             = var.database_name
  availability_zones        = var.availability_zones

  master_username                     = "hs_master"
  manage_master_user_password         = true
  master_user_secret_kms_key_id       = var.kms_key_arn
  iam_database_authentication_enabled = true

  storage_type                    = "aurora-iopt1"
  storage_encrypted               = true
  kms_key_id                      = var.kms_key_arn
  db_subnet_group_name            = var.db_subnet_group_name
  vpc_security_group_ids          = var.security_group_ids
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this[var.region_name].name

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = var.backup_window
  preferred_maintenance_window = var.maintenance_window
  copy_tags_to_snapshot        = true
  deletion_protection          = var.deletion_protection
  skip_final_snapshot          = false
  final_snapshot_identifier    = "${local.name}-final"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  # A promoted secondary moves the writer role, so the global membership is owned by the switch runbook.
  lifecycle {
    ignore_changes = [global_cluster_identifier]
  }

  tags = var.tags
}

resource "aws_rds_cluster_instance" "writer" {
  count = local.working ? 1 : 0

  identifier                      = "${local.name}-writer"
  cluster_identifier              = aws_rds_cluster.primary[0].id
  engine                          = aws_rds_cluster.primary[0].engine
  engine_version                  = aws_rds_cluster.primary[0].engine_version
  instance_class                  = var.writer_instance_class
  availability_zone               = var.writer_az
  promotion_tier                  = 0
  performance_insights_enabled    = true
  performance_insights_kms_key_id = var.kms_key_arn
  auto_minor_version_upgrade      = true
  copy_tags_to_snapshot           = true
  db_subnet_group_name            = var.db_subnet_group_name
  tags                            = var.tags
}

resource "aws_rds_cluster_instance" "reader" {
  count = local.working ? var.reader_count : 0

  identifier                      = "${local.name}-reader-${count.index}"
  cluster_identifier              = aws_rds_cluster.primary[0].id
  engine                          = aws_rds_cluster.primary[0].engine
  engine_version                  = aws_rds_cluster.primary[0].engine_version
  instance_class                  = var.reader_instance_class
  availability_zone               = local.reader_azs[count.index]
  promotion_tier                  = 1
  performance_insights_enabled    = true
  performance_insights_kms_key_id = var.kms_key_arn
  auto_minor_version_upgrade      = true
  copy_tags_to_snapshot           = true
  db_subnet_group_name            = var.db_subnet_group_name

  tags = var.tags
}

# No instance in a working-role secondary: storage only, so recovery regions run no compute.
resource "aws_rds_cluster" "secondary" {
  for_each = local.secondaries

  region                    = each.key
  cluster_identifier        = "${var.name_prefix}-${var.env}-${each.value.short}-${var.component}"
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  global_cluster_identifier = local.working ? aws_rds_global_cluster.this[0].id : var.global_cluster_identifier
  source_region             = var.primary_region

  iam_database_authentication_enabled = true
  storage_encrypted                   = true
  kms_key_id                          = each.value.kms_key_arn
  db_subnet_group_name                = each.value.db_subnet_group
  vpc_security_group_ids              = each.value.security_group_ids
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.this[each.key].name

  backup_retention_period   = var.backup_retention_days
  preferred_backup_window   = var.backup_window
  copy_tags_to_snapshot     = true
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name_prefix}-${var.env}-${each.value.short}-${var.component}-final"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  depends_on = [aws_rds_cluster_instance.writer]

  tags = var.tags
}

# Instances appear in a recovery region only at the switch, through recovery_instance_count.
resource "aws_rds_cluster_instance" "recovery" {
  count = local.working ? 0 : var.recovery_instance_count

  region                          = var.region_name
  identifier                      = "${local.name}-${count.index}"
  cluster_identifier              = aws_rds_cluster.secondary[var.region_name].id
  engine                          = aws_rds_cluster.secondary[var.region_name].engine
  engine_version                  = aws_rds_cluster.secondary[var.region_name].engine_version
  instance_class                  = var.writer_instance_class
  availability_zone               = var.availability_zones[count.index % 3]
  promotion_tier                  = count.index == 0 ? 0 : 1
  performance_insights_enabled    = true
  performance_insights_kms_key_id = var.kms_key_arn
  auto_minor_version_upgrade      = true
  copy_tags_to_snapshot           = true
  db_subnet_group_name            = var.db_subnet_group_name

  tags = var.tags
}

# The lag metric is published in the region of the secondary, so the alarm lives there.
resource "aws_cloudwatch_metric_alarm" "global_lag" {
  for_each = local.secondaries

  region              = each.key
  alarm_name          = "${aws_rds_cluster.secondary[each.key].cluster_identifier}-global-lag"
  alarm_description   = "Aurora global replication lag above the alert threshold; the RPO budget is 10 s"
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBReplicationLag"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  threshold           = var.lag_alarm_threshold_ms
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "ignore"
  alarm_actions       = compact([lookup(var.alarm_actions, each.key, "")])

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary[each.key].cluster_identifier
  }

  tags = var.tags
}

resource "aws_iam_role" "proxy" {
  count = local.proxy_enabled ? 1 : 0

  name = "${local.name}-proxy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "proxy" {
  count = local.proxy_enabled ? 1 : 0

  name = "read-db-secret"
  role = aws_iam_role.proxy[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [local.proxy_secret_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = [var.kms_key_arn]
      },
    ]
  })
}

resource "aws_db_proxy" "this" {
  count = local.proxy_enabled ? 1 : 0

  region                 = local.working ? null : var.region_name
  name                   = local.name
  engine_family          = "POSTGRESQL"
  require_tls            = true
  idle_client_timeout    = 1800
  role_arn               = aws_iam_role.proxy[0].arn
  vpc_subnet_ids         = var.proxy_subnet_ids
  vpc_security_group_ids = var.proxy_security_group_ids

  auth {
    auth_scheme               = "SECRETS"
    iam_auth                  = "REQUIRED"
    client_password_auth_type = "POSTGRES_SCRAM_SHA_256"
    secret_arn                = local.proxy_secret_arn
  }

  tags = var.tags
}

# 80% of max_connections leaves room for migrations and break-glass sessions.
resource "aws_db_proxy_default_target_group" "this" {
  count = local.proxy_enabled ? 1 : 0

  region        = local.working ? null : var.region_name
  db_proxy_name = aws_db_proxy.this[0].name

  connection_pool_config {
    max_connections_percent = 80
  }
}

resource "aws_db_proxy_target" "this" {
  count = local.proxy_enabled ? 1 : 0

  region                = local.working ? null : var.region_name
  db_proxy_name         = aws_db_proxy.this[0].name
  target_group_name     = aws_db_proxy_default_target_group.this[0].name
  db_cluster_identifier = local.proxy_cluster_id
}
