# Argo CD in shared-services registers the cluster from this secret (an ExternalSecret renders the cluster Secret); the value holds no credential.
resource "aws_secretsmanager_secret" "this" {
  # checkov:skip=CKV2_AWS_57: the value is an endpoint, a CA and a role ARN, rewritten on every apply; there is nothing to rotate
  name                    = "${var.name_prefix}/argocd/clusters/${var.argocd_cluster_name}"
  description             = "Argo CD registration of ${var.cluster_name}."
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = 7
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "this" {
  secret_id = aws_secretsmanager_secret.this.id
  secret_string = jsonencode({
    name        = var.argocd_cluster_name
    server      = var.cluster_endpoint
    caData      = var.certificate_authority_data
    roleARN     = var.controller_role_arn
    clusterName = var.cluster_name
    environment = var.environment
    region      = var.cluster_region
    # Vault in shared-services verifies the service account tokens of this cluster against its OIDC issuer (jwt auth mount k8s-<name>)
    oidcIssuer = var.oidc_issuer
  })
}

resource "aws_secretsmanager_secret_policy" "this" {
  secret_arn          = aws_secretsmanager_secret.this.arn
  block_public_policy = true
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "ExternalSecretsReads"
        Effect    = "Allow"
        Principal = { AWS = var.reader_role_arn }
        Action    = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource  = "*"
      },
      {
        Sid       = "VaultBootstrapReads"
        Effect    = "Allow"
        Principal = { AWS = var.vault_bootstrap_role_arn }
        Action    = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource  = "*"
      },
      {
        Sid       = "NobodyElseReads"
        Effect    = "Deny"
        Principal = "*"
        Action    = ["secretsmanager:GetSecretValue"]
        Resource  = "*"
        Condition = { ArnNotEquals = { "aws:PrincipalArn" = [var.reader_role_arn, var.writer_role_arn, var.vault_bootstrap_role_arn] } }
      },
    ]
  })
}
