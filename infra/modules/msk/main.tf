locals {
  name = "pay-${var.env}-${var.region_short}-${var.component}"

  # Topics are created from the YAML catalog by the kafka module, never by a producer.
  server_properties = join("\n", [
    "auto.create.topics.enable=false",
    "default.replication.factor=3",
    "min.insync.replicas=2",
    "num.partitions=64",
    "unclean.leader.election.enable=false",
    "log.retention.hours=${var.retention_hours}",
  ])

  cluster_arn   = aws_msk_cluster.this.arn
  topic_arn     = "${replace(local.cluster_arn, ":cluster/", ":topic/")}/*"
  group_arn     = "${replace(local.cluster_arn, ":cluster/", ":group/")}/*"
  sink_prefixes = "${var.sink_bucket_arn}/${var.sink_prefix}/*"
}

resource "aws_msk_configuration" "this" {
  name              = local.name
  description       = "RF 3, min ISR 2, no topic auto-creation"
  kafka_versions    = [var.kafka_version]
  server_properties = local.server_properties
}

resource "aws_msk_cluster" "this" {
  cluster_name           = local.name
  kafka_version          = var.kafka_version
  number_of_broker_nodes = var.broker_count
  enhanced_monitoring    = "PER_TOPIC_PER_PARTITION"

  broker_node_group_info {
    instance_type   = var.instance_type
    client_subnets  = var.client_subnets
    security_groups = var.security_group_ids
    az_distribution = "DEFAULT"

    storage_info {
      ebs_storage_info {
        volume_size = var.volume_size_gb
      }
    }
  }

  client_authentication {
    unauthenticated = false

    sasl {
      iam = true
    }
  }

  encryption_info {
    encryption_at_rest_kms_key_arn = var.kms_key_arn

    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  configuration_info {
    arn      = aws_msk_configuration.this.arn
    revision = aws_msk_configuration.this.latest_revision
  }

  open_monitoring {
    prometheus {
      jmx_exporter {
        enabled_in_broker = true
      }
      node_exporter {
        enabled_in_broker = true
      }
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = var.log_group_name
      }
    }
  }

  tags = var.tags
}

resource "aws_iam_role" "sink" {
  name = "${local.name}-s3-sink"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "kafkaconnect.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = var.account_id } }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "sink" {
  name = "kafka-to-s3"
  role = aws_iam_role.sink.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["kafka-cluster:Connect", "kafka-cluster:DescribeCluster"]
        Resource = [local.cluster_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["kafka-cluster:DescribeTopic", "kafka-cluster:ReadData"]
        Resource = [local.topic_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["kafka-cluster:AlterGroup", "kafka-cluster:DescribeGroup"]
        Resource = [local.group_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"]
        Resource = [local.sink_prefixes]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [var.sink_bucket_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource = [var.sink_kms_key_arn]
      },
    ]
  })
}
