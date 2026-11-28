mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::222222222222:role/mock" }
  }
}

variables {
  name_prefix              = "pay"
  region                   = "eu-central-1"
  region_short             = "euc1"
  account_id               = "222222222222"
  domain_arn               = "arn:aws:es:eu-central-1:222222222222:domain/pay-shared-euc1-logs"
  domain_endpoint          = "vpc-pay-shared-euc1-logs-abc.eu-central-1.es.amazonaws.com"
  cluster_name             = "pay-shared-services-euc1-central"
  oidc_provider_arn        = "arn:aws:iam::222222222222:oidc-provider/oidc.eks.eu-central-1.amazonaws.com/id/ABC"
  permissions_boundary_arn = "arn:aws:iam::222222222222:policy/workload-boundary"
  log_archive              = { bucket_name = "pay-security-euc1-log-archive", account_id = "666666666666" }
  subnet_ids               = ["subnet-1", "subnet-2", "subnet-3"]
  client_security_group_id = "sg-0001"
  kms_key_arn              = "arn:aws:kms:eu-central-1:222222222222:key/mrk-shared"
  logs_kms_key_arn         = "arn:aws:kms:eu-central-1:222222222222:key/mrk-logs"
  tags = {
    team          = "platform"
    owner         = "platform@example.com"
    "pci-scope"   = "out-of-scope"
    "data-class"  = "internal"
    "backup-tier" = "none"
  }
}

run "logstash_role_trusts_only_its_service_account" {
  command = plan

  assert {
    condition = (
      jsondecode(aws_iam_role.logstash.assume_role_policy).Statement[0].Condition.StringEquals["oidc.eks.eu-central-1.amazonaws.com/id/ABC:sub"] == "system:serviceaccount:monitoring:logstash" &&
      aws_iam_role.logstash.name == "pay-shared-services-euc1-logstash" &&
      aws_iam_role.logstash.permissions_boundary == var.permissions_boundary_arn
    )
    error_message = "IRSA trust pinned to monitoring/logstash under the boundary"
  }

  assert {
    condition     = toset(jsondecode(aws_iam_role_policy.logstash.policy).Statement[0].Action) == toset(["es:ESHttpPost", "es:ESHttpPut", "es:ESHttpGet"])
    error_message = "Logstash posts, puts and gets on the domain only"
  }

  assert {
    condition = (
      jsondecode(aws_iam_role_policy.reader["os-exporter"].policy).Statement[0].Action == ["es:ESHttpGet"] &&
      aws_eks_pod_identity_association.reader["os-exporter"].service_account == "opensearch-exporter" &&
      aws_eks_pod_identity_association.reader["grafana"].service_account == "grafana" &&
      aws_eks_pod_identity_association.reader["grafana"].cluster_name == "pay-shared-services-euc1-central"
    )
    error_message = "the exporter only gets, Grafana searches, both through Pod Identity on the central cluster"
  }
}

run "pipelines_read_the_archive_prefixes_into_the_audit_stream" {
  command = apply

  assert {
    condition = (
      yamldecode(aws_osis_pipeline.audit["cloudtrail"].pipeline_configuration_body)["audit-cloudtrail"].sink[0].opensearch.index == "logs-audit" &&
      yamldecode(aws_osis_pipeline.audit["eks"].pipeline_configuration_body)["audit-eks"].source.s3.notification_type == "sqs" &&
      yamldecode(aws_osis_pipeline.audit["eks"].pipeline_configuration_body)["audit-eks"].source.s3.sqs.queue_url == aws_sqs_queue.audit["eks"].url &&
      aws_osis_pipeline.audit["eks"].pipeline_name == "pay-audit-eks"
    )
    error_message = "CloudTrail and EKS audit go to logs-audit"
  }

  assert {
    condition     = alltrue([for g in aws_cloudwatch_log_group.pipeline : g.retention_in_days == 30])
    error_message = "pipeline logs have a retention"
  }

  assert {
    condition     = jsondecode(aws_sqs_queue_policy.audit["cloudtrail"].policy).Statement[0].Condition.ArnEquals["aws:SourceArn"] == "arn:aws:s3:::pay-security-euc1-log-archive"
    error_message = "only the log-archive bucket sends to the queues"
  }
}
