locals {
  name            = coalesce(var.domain_name, "${var.name_prefix}-${var.env}-${var.region_short}-${var.component}")
  multi_az        = var.availability_zone_count > 1
  domain_arn      = "arn:aws:es:${var.region_name}:${var.account_id}:domain/${local.name}"
  log_types       = ["ES_APPLICATION_LOGS", "SEARCH_SLOW_LOGS", "INDEX_SLOW_LOGS"]
  saml_enabled    = var.saml != null
  snapshot_role   = var.snapshot_bucket_arn != null
  custom_endpoint = var.custom_endpoint != null
}

# Dashboards answer on the admin host (behind the internal admin gateway) with a private certificate; SAML then uses that host.
resource "aws_acm_certificate" "custom" {
  count = local.custom_endpoint ? 1 : 0

  domain_name               = var.custom_endpoint.host
  certificate_authority_arn = var.custom_endpoint.certificate_authority_arn
  key_algorithm             = "EC_prime256v1"

  lifecycle {
    create_before_destroy = true
  }

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/opensearch/${local.name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = var.tags
}

# Log publishing needs a resource policy for the service; the source account condition keeps other accounts out.
resource "aws_cloudwatch_log_resource_policy" "this" {
  policy_name = "${local.name}-publishing"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "es.amazonaws.com" }
      Action    = ["logs:PutLogEvents", "logs:CreateLogStream"]
      Resource  = "${aws_cloudwatch_log_group.this.arn}:*"
      Condition = { StringEquals = { "aws:SourceAccount" = var.account_id } }
    }]
  })
}

resource "aws_security_group" "domain" {
  name        = "${local.name}-domain"
  description = "HTTPS to the ${local.name} domain from its clients only"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${local.name}-domain" })
}

# Attached by clients that have no security group of their own here, such as the OpenSearch Ingestion pipelines.
resource "aws_security_group" "client" {
  # checkov:skip=CKV2_AWS_5: attached by the ingestion pipelines of another stack
  name        = "${local.name}-client"
  description = "Clients of the ${local.name} domain"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${local.name}-client" })
}

resource "aws_vpc_security_group_ingress_rule" "clients" {
  # Static keys: the client group id is unknown until apply.
  for_each = merge({ client = aws_security_group.client.id }, { for i, g in var.client_security_group_ids : "external-${i}" => g })

  security_group_id            = aws_security_group.domain.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "HTTPS from a client of the domain"
}

# VPCs of other accounts reach the domain through the transit gateway, where their security groups cannot be referenced.
resource "aws_vpc_security_group_ingress_rule" "cidrs" {
  for_each = toset(var.client_cidr_blocks)

  security_group_id = aws_security_group.domain.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS from a VPC behind the transit gateway"
}

resource "aws_vpc_security_group_egress_rule" "client" {
  security_group_id            = aws_security_group.client.id
  referenced_security_group_id = aws_security_group.domain.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "HTTPS to the domain"
}

resource "aws_opensearch_domain" "this" {
  domain_name    = local.name
  engine_version = var.engine_version

  cluster_config {
    instance_type            = var.data_instance_type
    instance_count           = var.data_node_count
    zone_awareness_enabled   = local.multi_az
    dedicated_master_enabled = var.dedicated_master_count > 0
    dedicated_master_type    = var.dedicated_master_count > 0 ? var.master_instance_type : null
    dedicated_master_count   = var.dedicated_master_count > 0 ? var.dedicated_master_count : null
    warm_enabled             = var.warm_node_count > 0
    warm_type                = var.warm_node_count > 0 ? var.warm_instance_type : null
    warm_count               = var.warm_node_count > 0 ? var.warm_node_count : null

    dynamic "zone_awareness_config" {
      for_each = local.multi_az ? [var.availability_zone_count] : []

      content {
        availability_zone_count = zone_awareness_config.value
      }
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
    enforce_https                   = true
    tls_security_policy             = "Policy-Min-TLS-1-2-PFS-2023-10"
    custom_endpoint_enabled         = local.custom_endpoint
    custom_endpoint                 = local.custom_endpoint ? var.custom_endpoint.host : null
    custom_endpoint_certificate_arn = local.custom_endpoint ? aws_acm_certificate.custom[0].arn : null
  }

  vpc_options {
    subnet_ids         = slice(var.subnet_ids, 0, var.availability_zone_count)
    security_group_ids = [aws_security_group.domain.id]
  }

  advanced_security_options {
    enabled                        = true
    anonymous_auth_enabled         = false
    internal_user_database_enabled = false

    master_user_options {
      master_user_arn = var.master_user_arn
    }
  }

  # SAML sessions of Dashboards are not SigV4-signed, so the policy admits any principal and fine-grained access control decides.
  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = var.access_principal_arns }
      Action    = "es:ESHttp*"
      Resource  = "${local.domain_arn}/*"
    }]
  })

  dynamic "log_publishing_options" {
    for_each = toset(local.log_types)

    content {
      log_type                 = log_publishing_options.value
      cloudwatch_log_group_arn = aws_cloudwatch_log_group.this.arn
    }
  }

  lifecycle {
    precondition {
      condition     = length(local.name) >= 3 && length(local.name) <= 28
      error_message = "OpenSearch domain names are limited to 3-28 characters."
    }
    precondition {
      condition     = var.data_node_count % var.availability_zone_count == 0
      error_message = "data_node_count must be a multiple of availability_zone_count."
    }
    precondition {
      condition     = var.warm_node_count == 0 || var.dedicated_master_count > 0
      error_message = "UltraWarm needs dedicated master nodes."
    }
  }

  depends_on = [aws_cloudwatch_log_resource_policy.this]

  tags = var.tags
}

# Environment accounts reach the domain through an OpenSearch-managed VPC endpoint in their own VPC (opensearch-endpoint module).
resource "aws_opensearch_authorize_vpc_endpoint_access" "this" {
  for_each = toset(var.endpoint_account_ids)

  domain_name = aws_opensearch_domain.this.domain_name
  account     = each.value
}

# Dashboards sign-in through the identity provider; the groups attribute becomes the backend roles of the role mappings.
resource "aws_opensearch_domain_saml_options" "this" {
  count = local.saml_enabled ? 1 : 0

  domain_name = aws_opensearch_domain.this.domain_name

  saml_options {
    enabled                 = true
    roles_key               = var.saml.roles_key
    master_backend_role     = var.saml.master_backend_role
    session_timeout_minutes = var.saml.session_timeout_minutes

    idp {
      entity_id        = var.saml.entity_id
      metadata_content = var.saml.metadata_content
    }
  }
}

# Role the Snapshot Management policy assumes to write to the S3 repository.
resource "aws_iam_role" "snapshot" {
  count = local.snapshot_role ? 1 : 0

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
  count = local.snapshot_role ? 1 : 0

  name = "write-snapshots"
  role = aws_iam_role.snapshot[0].id

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
        Resource = [aws_iam_role.snapshot[0].arn]
      },
    ]
  })
}
