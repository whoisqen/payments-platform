locals {
  name = "${var.name_prefix}-${var.env}-${var.region_short}-${var.component}"
}

resource "aws_opensearch_domain" "this" {
  domain_name    = local.name
  engine_version = var.engine_version

  cluster_config {
    instance_type            = var.data_instance_type
    instance_count           = var.data_node_count
    zone_awareness_enabled   = true
    dedicated_master_enabled = true
    dedicated_master_type    = var.master_instance_type
    dedicated_master_count   = 3
    warm_enabled             = true
    warm_type                = var.warm_instance_type
    warm_count               = var.warm_node_count

    zone_awareness_config {
      availability_zone_count = 3
    }
  }

  ebs_options {
    ebs_enabled = true
    volume_type = "gp3"
    volume_size = var.volume_size_gb
  }

  encrypt_at_rest {
    enabled    = true
    kms_key_id = var.kms_key_arn
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-PFS-2023-10"
  }

  vpc_options {
    subnet_ids         = var.subnet_ids
    security_group_ids = var.security_group_ids
  }

  advanced_security_options {
    enabled                        = true
    internal_user_database_enabled = false

    master_user_options {
      master_user_arn = var.master_user_arn
    }
  }

  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = var.access_principal_arns }
      Action    = "es:ESHttp*"
      Resource  = "arn:aws:es:${var.region_name}:${var.account_id}:domain/${local.name}/*"
    }]
  })

  log_publishing_options {
    log_type                 = "ES_APPLICATION_LOGS"
    cloudwatch_log_group_arn = var.log_group_arn
  }

  log_publishing_options {
    log_type                 = "SEARCH_SLOW_LOGS"
    cloudwatch_log_group_arn = var.log_group_arn
  }

  lifecycle {
    precondition {
      condition     = length(local.name) <= 28
      error_message = "OpenSearch domain names are limited to 28 characters."
    }
  }

  tags = var.tags
}

# Role the Snapshot Management policy assumes to write to the S3 repository.
resource "aws_iam_role" "snapshot" {
  name = "${local.name}-snapshot"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "es.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "snapshot" {
  name = "write-snapshots"
  role = aws_iam_role.snapshot.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [var.snapshot_bucket_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["${var.snapshot_bucket_arn}/${var.snapshot_prefix}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource = [var.snapshot_kms_key_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = [aws_iam_role.snapshot.arn]
      },
    ]
  })
}
