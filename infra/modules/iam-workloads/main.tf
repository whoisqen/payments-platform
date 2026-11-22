locals {
  region_short = { "eu-central-1" = "euc1", "us-east-1" = "use1", "us-east-2" = "use2" }[var.region]
  prefix       = "pay-${var.environment}-${local.region_short}-${var.cell}"

  services = {
    router             = "router"
    locker             = "locker"
    drainer            = "drainer"
    scheduler          = "scheduler"
    "external-secrets" = "external-secrets"
  }

  memorydb_statement = { for svc, user in var.memorydb.users : svc => [{
    Effect   = "Allow"
    Action   = ["memorydb:Connect"]
    Resource = [var.memorydb.cluster_arn, "arn:aws:memorydb:${var.region}:${var.account_id}:user/${user}"]
  }] }

  database_statement = { for svc, arns in var.rds_db_connect_arns : svc => [{
    Effect   = "Allow"
    Action   = ["rds-db:connect"]
    Resource = arns
  }] if length(arns) > 0 }

  merchant_map_statement = [{
    Effect   = "Allow"
    Action   = ["dynamodb:GetItem", "dynamodb:BatchGetItem", "dynamodb:Query"]
    Resource = [var.dynamodb_table_arn]
  }]

  # Only the locker reaches its key; the locker holds the only place where card data is decrypted.
  locker_key_statement = [{
    Effect   = "Allow"
    Action   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    Resource = [var.locker_kms_key_arn]
  }]

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

  statements = {
    router             = concat(lookup(local.memorydb_statement, "router", []), lookup(local.database_statement, "router", []), local.merchant_map_statement)
    locker             = concat(lookup(local.database_statement, "locker", []), local.locker_key_statement)
    drainer            = concat(lookup(local.memorydb_statement, "drainer", []), lookup(local.database_statement, "drainer", []))
    scheduler          = concat(lookup(local.memorydb_statement, "scheduler", []), lookup(local.database_statement, "scheduler", []), local.merchant_map_statement)
    "external-secrets" = local.secrets_statements
  }
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
  service_account = each.value
  role_arn        = aws_iam_role.this[each.key].arn
  tags            = var.tags
}
