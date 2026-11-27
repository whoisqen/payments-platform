locals {
  region_short = join("", [split("-", var.region)[0], substr(split("-", var.region)[1], 0, 1), split("-", var.region)[2]])
  prefix       = "${var.name_prefix}-${var.environment}-${local.region_short}-${var.cell}"

  # Service -> namespace of its service account.
  services = merge(
    { for s in var.services : s => var.workload_namespace },
    { "external-secrets" = "external-secrets" },
    var.migrator == null ? {} : { migrator = var.workload_namespace },
  )

  memorydb_statement = var.memorydb == null ? {} : { for svc, user in var.memorydb.users : svc => [{
    Effect   = "Allow"
    Action   = ["memorydb:Connect"]
    Resource = [var.memorydb.cluster_arn, "arn:aws:memorydb:${var.region}:${var.account_id}:user/${user}"]
  }] }

  database_statement = { for svc, arns in var.rds_db_connect_arns : svc => [{
    Effect   = "Allow"
    Action   = ["rds-db:connect"]
    Resource = arns
  }] if length(arns) > 0 }

  merchant_map_statement = var.dynamodb_table_arn == null ? [] : [{
    Effect   = "Allow"
    Action   = ["dynamodb:GetItem", "dynamodb:BatchGetItem", "dynamodb:Query"]
    Resource = [var.dynamodb_table_arn]
  }]

  # Only the locker reaches its key; the locker holds the only place where card data is decrypted.
  locker_key_statement = var.locker_kms_key_arn == null ? [] : [{
    Effect   = "Allow"
    Action   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    Resource = [var.locker_kms_key_arn]
  }]

  # Router writes encrypted merchant data with the cell key; drainer and scheduler only read what it wrote.
  cell_key_actions = {
    router    = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    drainer   = ["kms:Decrypt", "kms:DescribeKey"]
    scheduler = ["kms:Decrypt", "kms:DescribeKey"]
  }
  cell_key_statement = var.cell_kms_key_arn == null ? {} : { for svc, actions in local.cell_key_actions : svc => [{
    Effect   = "Allow"
    Action   = actions
    Resource = [var.cell_kms_key_arn]
  }] }

  migrator_statements = var.migrator == null ? null : [
    { Sid = "LoginAsMigrator", Effect = "Allow", Action = ["rds-db:connect"], Resource = var.migrator.db_connect_arns },
    { Sid = "PreMigrationBackup", Effect = "Allow", Action = ["backup:StartBackupJob"], Resource = [var.migrator.backup_vault_arn] },
    { Sid = "ReadRecoveryPoint", Effect = "Allow", Action = ["backup:DescribeRecoveryPoint"], Resource = ["arn:aws:rds:${var.region}:${var.account_id}:cluster-snapshot:awsbackup:*"] },
    { Sid = "ReadBackupJob", Effect = "Allow", Action = ["backup:DescribeBackupJob"], Resource = ["*"] },
    {
      Sid       = "PassBackupRole"
      Effect    = "Allow"
      Action    = ["iam:PassRole"]
      Resource  = [var.migrator.backup_role_arn]
      Condition = { StringEquals = { "iam:PassedToService" = "backup.amazonaws.com" } }
    },
  ]

  secrets_statements = [for s in [
    {
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = var.secret_arns
    },
    {
      Effect    = "Allow"
      Action    = ["kms:Decrypt"]
      Resource  = [var.secrets_kms_key_arn]
      Condition = { StringEquals = { "kms:ViaService" = "secretsmanager.${var.region}.amazonaws.com" } }
    },
  ] : s if length(var.secret_arns) > 0]

  all_statements = {
    router             = concat(try(local.memorydb_statement["router"], []), try(local.database_statement["router"], []), local.merchant_map_statement, try(local.cell_key_statement["router"], []))
    locker             = concat(try(local.database_statement["locker"], []), local.locker_key_statement)
    drainer            = concat(try(local.memorydb_statement["drainer"], []), try(local.database_statement["drainer"], []), try(local.cell_key_statement["drainer"], []))
    scheduler          = concat(try(local.memorydb_statement["scheduler"], []), try(local.database_statement["scheduler"], []), local.merchant_map_statement, try(local.cell_key_statement["scheduler"], []))
    "external-secrets" = local.secrets_statements
  }
  statements = { for svc, s in local.all_statements : svc => s if contains(keys(local.services), svc) }
}

resource "aws_iam_role" "this" {
  for_each = local.services

  name                 = "${local.prefix}-${each.key}"
  permissions_boundary = var.permissions_boundary_arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Condition = {
        StringEquals = { "aws:SourceAccount" = var.account_id }
        ArnEquals    = { "aws:SourceArn" = var.cluster_arn }
      }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "this" {
  for_each = { for svc, s in local.statements : svc => s if length(s) > 0 }

  name = "least-privilege"
  role = aws_iam_role.this[each.key].id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = each.value
  })
}

resource "aws_iam_role_policy_attachment" "deny_recovery_writes" {
  for_each = local.services

  role       = aws_iam_role.this[each.key].name
  policy_arn = var.deny_recovery_writes_policy_arn
}

resource "aws_eks_pod_identity_association" "this" {
  for_each = local.services

  cluster_name    = var.cluster_name
  namespace       = each.value
  service_account = each.key
  role_arn        = aws_iam_role.this[each.key].arn
  tags            = var.tags
}

# Event producers get the MSK producer policy (IAM auth, write only) of the analytics cluster.
resource "aws_iam_role_policy_attachment" "kafka_producer" {
  for_each = var.kafka_producer_policy_arn == null ? toset([]) : toset([for p in var.kafka_producers : p if contains(var.services, p)])

  role       = aws_iam_role.this[each.key].name
  policy_arn = var.kafka_producer_policy_arn
}

# YACE exports CloudWatch metrics to Prometheus; the CloudWatch read and tag discovery APIs have no resource-level scoping.
resource "aws_iam_role" "yace" {
  count = var.yace.enabled ? 1 : 0

  name                 = "${local.prefix}-yace"
  permissions_boundary = var.permissions_boundary_arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Condition = {
        StringEquals = { "aws:SourceAccount" = var.account_id }
        ArnEquals    = { "aws:SourceArn" = var.cluster_arn }
      }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "yace" {
  count = var.yace.enabled ? 1 : 0

  name = "cloudwatch-read"
  role = aws_iam_role.yace[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "ReadMetricsAndTags"
      Effect   = "Allow"
      Action   = ["cloudwatch:GetMetricData", "cloudwatch:GetMetricStatistics", "cloudwatch:ListMetrics", "tag:GetResources"]
      Resource = "*"
    }]
  })
}

resource "aws_eks_pod_identity_association" "yace" {
  count = var.yace.enabled ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.yace.namespace
  service_account = var.yace.service_account
  role_arn        = aws_iam_role.yace[0].arn
  tags            = var.tags
}

# Separate from the other policies: DescribeBackupJob has no resource-level scoping and recovery point names are generated by AWS Backup.
resource "aws_iam_role_policy" "migrator" {
  count = var.migrator == null ? 0 : 1

  name   = "migrate-and-snapshot"
  role   = aws_iam_role.this["migrator"].id
  policy = jsonencode({ Version = "2012-10-17", Statement = local.migrator_statements })
}
