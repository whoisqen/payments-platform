locals {
  name = "${var.name_prefix}-${var.environment}-${var.region_short}"
  # Grafana searches with POST; the exporter only reads statistics.
  readers = {
    "os-exporter" = merge(var.readers.exporter, { actions = ["es:ESHttpGet"] })
    "grafana"     = merge(var.readers.grafana, { actions = ["es:ESHttpGet", "es:ESHttpPost"] })
  }
  oidc_host  = element(split("oidc-provider/", var.oidc_provider_arn), 1)
  bucket_arn = "arn:aws:s3:::${var.log_archive.bucket_name}"
  sink = [{
    opensearch = {
      hosts      = ["https://${var.domain_endpoint}"]
      index_type = "custom"
      index      = var.audit_stream
      action     = "create"
      aws        = { region = var.region, sts_role_arn = aws_iam_role.pipeline.arn }
    }
  }]

  # One pipeline per source: CloudTrail files hold a Records array; the EKS export holds CloudWatch Logs envelopes of all five log types.
  sources = {
    cloudtrail = {
      codec = { json = { key_name = "Records" } }
      processor = [
        { date = { match = [{ key = "eventTime", patterns = ["yyyy-MM-dd'T'HH:mm:ss'Z'"] }], destination = "@timestamp" } },
        { add_entries = { entries = [{ key = "log.source", value = "cloudtrail" }] } },
      ]
    }
    eks = {
      codec = { json = { key_name = "logEvents", include_keys = ["logGroup", "logStream"] } }
      processor = [
        { drop_events = { drop_when = "not startsWith(/logStream, \"kube-apiserver-audit\")" } },
        { parse_json = { source = "message", destination = "audit" } },
        { date = { match = [{ key = "timestamp", patterns = ["epoch_milli"] }], destination = "@timestamp" } },
        { delete_entries = { with_keys = ["message"] } },
        { add_entries = { entries = [{ key = "log.source", value = "eks-audit" }] } },
      ]
    }
  }

  pipelines = { for k, s in local.sources : k => {
    version = "2"
    "audit-${k}" = {
      source = {
        s3 = {
          acknowledgments   = true
          compression       = "gzip"
          codec             = s.codec
          bucket_owners     = { (var.log_archive.bucket_name) = var.log_archive.account_id }
          aws               = { region = var.region, sts_role_arn = aws_iam_role.pipeline.arn }
          notification_type = "sqs"
          sqs               = { queue_url = aws_sqs_queue.audit[k].url, maximum_messages = 10, visibility_timeout = "300s" }
        }
      }
      processor = s.processor
      sink      = local.sink
    }
  } }
}

# The log-archive bucket notifies one queue per source on every new object, so only new logs are read (never the Glacier tier).
resource "aws_sqs_queue" "audit" {
  for_each = local.sources

  name                       = "${local.name}-audit-${each.key}"
  sqs_managed_sse_enabled    = true
  message_retention_seconds  = 1209600
  visibility_timeout_seconds = 300

  tags = var.tags
}

resource "aws_sqs_queue_policy" "audit" {
  for_each = local.sources

  queue_url = aws_sqs_queue.audit[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "LogArchiveEvents"
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.audit[each.key].arn
      Condition = {
        ArnEquals    = { "aws:SourceArn" = local.bucket_arn }
        StringEquals = { "aws:SourceAccount" = var.log_archive.account_id }
      }
    }]
  })
}

# Logstash on the central cluster writes the application logs of every environment (IRSA, one service account).
resource "aws_iam_role" "logstash" {
  name                 = "${local.name}-logstash"
  permissions_boundary = var.permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = var.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_host}:sub" = "system:serviceaccount:${var.logstash_service_account.namespace}:${var.logstash_service_account.name}"
          "${local.oidc_host}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "logstash" {
  name = "write-logs"
  role = aws_iam_role.logstash.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "DomainHttp"
      Effect   = "Allow"
      Action   = ["es:ESHttpPost", "es:ESHttpPut", "es:ESHttpGet"]
      Resource = ["${var.domain_arn}/*"]
    }]
  })
}

# Readers on the central cluster through Pod Identity: the metrics exporter (statistics) and Grafana (searches of logs-app-*).
resource "aws_iam_role" "reader" {
  for_each = local.readers

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

resource "aws_iam_role_policy" "reader" {
  for_each = local.readers

  name = "read-domain"
  role = aws_iam_role.reader[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "DomainHttp"
      Effect   = "Allow"
      Action   = each.value.actions
      Resource = ["${var.domain_arn}/*"]
    }]
  })
}

resource "aws_eks_pod_identity_association" "reader" {
  for_each = local.readers

  cluster_name    = var.cluster_name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = aws_iam_role.reader[each.key].arn

  tags = var.tags
}

resource "aws_iam_role" "pipeline" {
  name                 = "${local.name}-audit-ingest"
  permissions_boundary = var.permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "osis-pipelines.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = var.account_id } }
    }]
  })

  tags = var.tags
}

# The log-archive bucket and key policies admit this role by name (log-archive input ingest_reader_principal_arns).
resource "aws_iam_role_policy" "pipeline" {
  name = "read-archive-write-audit"
  role = aws_iam_role.pipeline.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DescribeDomain"
        Effect   = "Allow"
        Action   = ["es:DescribeDomain"]
        Resource = [var.domain_arn]
      },
      {
        Sid      = "DomainHttp"
        Effect   = "Allow"
        Action   = ["es:ESHttp*"]
        Resource = ["${var.domain_arn}/*"]
      },
      {
        Sid      = "ConsumeArchiveEvents"
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:ChangeMessageVisibility", "sqs:GetQueueAttributes"]
        Resource = [for q in aws_sqs_queue.audit : q.arn]
      },
      {
        Sid       = "ListArchivePrefixes"
        Effect    = "Allow"
        Action    = ["s3:ListBucket"]
        Resource  = [local.bucket_arn]
        Condition = { StringLike = { "s3:prefix" = [for p in values(var.log_archive.prefixes) : "${p}*"] } }
      },
      {
        Sid      = "ReadArchivePrefixes"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = [for p in values(var.log_archive.prefixes) : "${local.bucket_arn}/${p}*"]
      },
      {
        Sid       = "DecryptArchive"
        Effect    = "Allow"
        Action    = ["kms:Decrypt"]
        Resource  = ["arn:aws:kms:${var.region}:${var.log_archive.account_id}:key/*"]
        Condition = { StringEquals = { "kms:ViaService" = "s3.${var.region}.amazonaws.com" } }
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "pipeline" {
  for_each = local.sources

  name              = "/aws/vendedlogs/OpenSearchIngestion/${local.name}-audit-${each.key}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  tags = var.tags
}

resource "aws_osis_pipeline" "audit" {
  for_each = local.sources

  pipeline_name               = "${var.name_prefix}-audit-${each.key}"
  pipeline_role_arn           = aws_iam_role.pipeline.arn
  min_units                   = var.units.min
  max_units                   = var.units.max
  pipeline_configuration_body = yamlencode(local.pipelines[each.key])

  vpc_options {
    subnet_ids         = var.subnet_ids
    security_group_ids = [var.client_security_group_id]
  }

  encryption_at_rest_options {
    kms_key_arn = var.kms_key_arn
  }

  log_publishing_options {
    is_logging_enabled = true

    cloudwatch_log_destination {
      log_group = aws_cloudwatch_log_group.pipeline[each.key].name
    }
  }

  depends_on = [aws_iam_role_policy.pipeline]

  tags = var.tags
}
