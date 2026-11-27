locals {
  region_short = join("", [split("-", var.region)[0], substr(split("-", var.region)[1], 0, 1), split("-", var.region)[2]])
  role_name    = "${var.name_prefix}-${var.environment}-${local.region_short}-central-external-secrets"
  secret_scope = "${var.name_prefix}/${var.environment}"

  # Shells of the secrets that deploy/ reads and no other stack creates (the */oidc secrets belong to okta-sso).
  # description names the JSON keys, or says the value is plain text.
  secrets = {
    "alertmanager/deadmans-switch-url"     = "Alertmanager: URL of the dead man's switch heartbeat receiver (plain text)"
    "alertmanager/fallback-webhook-url"    = "Alertmanager: webhook of the fallback receiver (plain text)"
    "alertmanager/slack-payments-alerts"   = "Alertmanager: Slack webhook of the payments alerts channel (plain text)"
    "alertmanager/slack-payments-critical" = "Alertmanager: Slack webhook of the payments critical channel (plain text)"
    "alertmanager/slack-security"          = "Alertmanager: Slack webhook of the security channel (plain text)"
    "grafana/admin"                        = "Grafana: built-in administrator, JSON keys user and password"
    "grafana/database"                     = "Grafana: database connection, JSON keys host, name, user and password"
    "otel-collector/tls"                   = "OpenTelemetry collector: TLS material, JSON keys ca.crt, tls.crt and tls.key (PEM)"
    "sentry/admin-password"                = "Sentry: password of the first administrator (plain text)"
    "sentry/clickhouse-password"           = "Sentry: ClickHouse password (plain text)"
    "sentry/launchpad-rpc-secret"          = "Sentry: shared secret of the launchpad RPC (plain text)"
    "sentry/postgres-password"             = "Sentry: PostgreSQL password (plain text)"
    "sentry/postgres-replication-password" = "Sentry: PostgreSQL replication password (plain text)"
    "sentry/redis-password"                = "Sentry: Redis password (plain text)"
    "sentry/system-secret-key"             = "Sentry: system.secret-key (plain text)"
  }

  generated = toset(var.generated_secrets)

  secret_arn_pattern = "arn:aws:secretsmanager:${var.region}:${var.account_id}:secret:${local.secret_scope}/*"
}

resource "aws_secretsmanager_secret" "this" {
  for_each = local.secrets

  name                    = "${local.secret_scope}/${each.key}"
  description             = each.value
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = var.secret_recovery_window_days
  tags                    = var.tags
}

resource "random_password" "this" {
  for_each = local.generated

  length  = each.key == "sentry/system-secret-key" ? 64 : 40
  special = false
}

# Only the secrets named in generated_secrets get a value; the others stay empty shells until the owner enters the value.
resource "aws_secretsmanager_secret_version" "generated" {
  for_each = local.generated

  secret_id     = aws_secretsmanager_secret.this[each.key].id
  secret_string = each.key == "grafana/admin" ? jsonencode({ user = "admin", password = random_password.this[each.key].result }) : random_password.this[each.key].result

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_iam_role" "external_secrets" {
  name                 = local.role_name
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

resource "aws_iam_role_policy" "external_secrets" {
  name = "read-secrets"
  role = aws_iam_role.external_secrets.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadSecretsOfTheEnvironment"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = [local.secret_arn_pattern]
      },
      {
        Sid       = "DecryptThroughSecretsManager"
        Effect    = "Allow"
        Action    = ["kms:Decrypt"]
        Resource  = [var.kms_key_arn]
        Condition = { StringEquals = { "kms:ViaService" = "secretsmanager.${var.region}.amazonaws.com" } }
      },
      # Vault runs in shared-services: its init secret holds the recovery keys and is read only by the audited break-glass role.
      {
        Sid      = "NeverReadVaultSecrets"
        Effect   = "Deny"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = ["arn:aws:secretsmanager:${var.region}:${var.account_id}:secret:${var.name_prefix}/shared-services/vault/*"]
      },
      {
        Sid    = "NeverWriteSecrets"
        Effect = "Deny"
        Action = [
          "secretsmanager:CancelRotateSecret",
          "secretsmanager:CreateSecret",
          "secretsmanager:DeleteResourcePolicy",
          "secretsmanager:DeleteSecret",
          "secretsmanager:PutResourcePolicy",
          "secretsmanager:PutSecretValue",
          "secretsmanager:RemoveRegionsFromReplication",
          "secretsmanager:ReplicateSecretToRegions",
          "secretsmanager:RestoreSecret",
          "secretsmanager:RotateSecret",
          "secretsmanager:StopReplicationToReplica",
          "secretsmanager:TagResource",
          "secretsmanager:UntagResource",
          "secretsmanager:UpdateSecret",
          "secretsmanager:UpdateSecretVersionStage",
        ]
        Resource = ["*"]
      },
      {
        Sid    = "NeverEncryptOrGrant"
        Effect = "Deny"
        Action = [
          "kms:CreateGrant",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:GenerateDataKeyWithoutPlaintext",
          "kms:ReEncryptFrom",
          "kms:ReEncryptTo",
          "kms:ScheduleKeyDeletion",
          "kms:PutKeyPolicy",
        ]
        Resource = [var.kms_key_arn]
      },
    ]
  })
}

resource "aws_eks_pod_identity_association" "external_secrets" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account
  role_arn        = aws_iam_role.external_secrets.arn
  tags            = var.tags
}
