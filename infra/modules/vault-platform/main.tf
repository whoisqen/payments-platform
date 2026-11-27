locals {
  name = "${var.name_prefix}-${var.env}-${var.region_short}-vault"

  roles = {
    server    = var.server_service_account
    snapshot  = var.snapshot_service_account
    bootstrap = var.bootstrap_service_account
  }

  secret_arn_pattern = "arn:aws:secretsmanager:${var.region}:${var.account_id}:secret:${var.name_prefix}/${var.env}/vault/*"
}

# Regional on purpose: the standby region seals with its own key, not a replica of the working one.
module "unseal_key" {
  source = "../kms"

  account_id   = var.account_id
  region       = var.region
  environment  = var.env
  name_prefix  = var.name_prefix
  component    = "vault-unseal"
  multi_region = false
  tags         = var.tags
}

resource "aws_iam_role" "this" {
  for_each = local.roles

  name                 = "${local.name}-${each.key}"
  permissions_boundary = var.permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = var.tags
}

resource "aws_eks_pod_identity_association" "this" {
  for_each = local.roles

  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = each.value
  role_arn        = aws_iam_role.this[each.key].arn

  tags = var.tags
}

resource "aws_iam_role_policy" "server" {
  name = "awskms-seal"
  role = aws_iam_role.this["server"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "UnsealKey"
      Effect   = "Allow"
      Action   = ["kms:Encrypt", "kms:Decrypt", "kms:DescribeKey"]
      Resource = [module.unseal_key.key_arn]
    }]
  })
}

# No read or delete: the bucket lifecycle expires snapshots and Object Lock keeps them until then.
resource "aws_iam_role_policy" "snapshot" {
  name = "raft-snapshots"
  role = aws_iam_role.this["snapshot"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "WriteSnapshots"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:AbortMultipartUpload"]
        Resource = ["${var.snapshot_bucket_arn}/${var.snapshot_prefix}*"]
      },
      {
        Sid      = "ListBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [var.snapshot_bucket_arn]
      },
      {
        Sid      = "BucketKey"
        Effect   = "Allow"
        Action   = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource = [var.snapshot_kms_key_arn]
      },
    ]
  })
}

resource "aws_iam_role_policy" "bootstrap" {
  name = "bootstrap-secrets"
  role = aws_iam_role.this["bootstrap"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "WriteVaultSecrets"
        Effect   = "Allow"
        Action   = ["secretsmanager:CreateSecret", "secretsmanager:PutSecretValue", "secretsmanager:DescribeSecret"]
        Resource = [local.secret_arn_pattern]
      },
      {
        # The Argo CD registrations of every cluster name its OIDC issuer: the bootstrap configures one jwt auth mount per cluster
        Sid      = "ReadClusterRegistrations"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = ["arn:aws:secretsmanager:${var.region}:${var.account_id}:secret:${var.name_prefix}/argocd/clusters/*"]
      },
      {
        Sid       = "SecretsKey"
        Effect    = "Allow"
        Action    = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource  = [var.secrets_kms_key_arn]
        Condition = { StringEquals = { "kms:ViaService" = "secretsmanager.${var.region}.amazonaws.com" } }
      },
    ]
  })
}
