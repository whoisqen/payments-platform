mock_provider "aws" {}

variables {
  name_prefix        = "pay"
  env                = "prod"
  region_short       = "euc1"
  account_id         = "111111111111"
  kms_key_arn        = "arn:aws:kms:eu-central-1:111111111111:key/mrk-0003"
  client_subnets     = ["subnet-1", "subnet-2", "subnet-3"]
  security_group_ids = ["sg-0001"]
  logs_kms_key_arn   = "arn:aws:kms:eu-central-1:111111111111:key/mrk-0005"
  sink_bucket_arn    = "arn:aws:s3:::pay-prod-euc1-event-archive"
  sink_kms_key_arn   = "arn:aws:kms:eu-central-1:111111111111:key/mrk-0004"

  tags = {
    team          = "data"
    owner         = "data@example.com"
    "pci-scope"   = "connected"
    "data-class"  = "internal"
    "backup-tier" = "none"
  }
}

run "cluster_is_durable_and_authenticated" {
  command = plan

  assert {
    condition     = aws_msk_cluster.this.number_of_broker_nodes == 9 && aws_msk_cluster.this.cluster_name == "pay-prod-euc1-msk"
    error_message = "nine brokers with the standard name"
  }

  assert {
    condition = (
      aws_msk_cluster.this.client_authentication[0].sasl[0].iam &&
      !aws_msk_cluster.this.client_authentication[0].unauthenticated &&
      aws_msk_cluster.this.encryption_info[0].encryption_in_transit[0].client_broker == "TLS" &&
      aws_msk_cluster.this.encryption_info[0].encryption_in_transit[0].in_cluster
    )
    error_message = "IAM only, TLS everywhere"
  }

  assert {
    condition = (
      strcontains(aws_msk_configuration.this.server_properties, "min.insync.replicas=2") &&
      strcontains(aws_msk_configuration.this.server_properties, "default.replication.factor=3") &&
      strcontains(aws_msk_configuration.this.server_properties, "auto.create.topics.enable=false")
    )
    error_message = "RF 3, min ISR 2, no auto-created topics"
  }
}

run "sink_writes_only_under_its_prefix" {
  command = plan

  assert {
    condition     = alltrue([for s in output.sink_bucket_policy_statements : s.Effect == "Allow"]) && output.sink_bucket_policy_statements[0].Resource[0] == "arn:aws:s3:::pay-prod-euc1-event-archive/events/*"
    error_message = "sink statements are scoped to the events prefix"
  }
}

run "logs_go_to_an_encrypted_group_of_the_cluster" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.brokers.name == "/aws/msk/pay-prod-euc1-msk" && aws_cloudwatch_log_group.brokers.kms_key_id == var.logs_kms_key_arn
    error_message = "broker logs land in /aws/msk/<name> encrypted with the logs key"
  }
}

run "producer_writes_but_never_reads" {
  command = apply

  override_resource {
    target = aws_msk_configuration.this
    values = { arn = "arn:aws:kafka:eu-central-1:111111111111:configuration/pay-prod-euc1-msk/cfg-1" }
  }

  override_resource {
    target = aws_msk_cluster.this
    values = {
      arn                        = "arn:aws:kafka:eu-central-1:111111111111:cluster/pay-prod-euc1-msk/abcd-1234"
      bootstrap_brokers_sasl_iam = "b-1.pay:9098,b-2.pay:9098,b-3.pay:9098"
    }
  }

  assert {
    condition = (
      alltrue([for s in jsondecode(aws_iam_policy.producer.policy).Statement : alltrue([for a in s.Action : !contains(["kafka-cluster:ReadData", "kafka-cluster:AlterGroup", "kafka-cluster:AlterCluster", "kafka-cluster:CreateTopic", "kafka-cluster:DeleteTopic"], a)])]) &&
      contains(flatten([for s in jsondecode(aws_iam_policy.producer.policy).Statement : s.Action]), "kafka-cluster:WriteData") &&
      alltrue([for s in jsondecode(aws_iam_policy.producer.policy).Statement : !contains(s.Resource, "*")]) &&
      contains(flatten([for s in jsondecode(aws_iam_policy.producer.policy).Statement : s.Resource]), "arn:aws:kafka:eu-central-1:111111111111:topic/pay-prod-euc1-msk/abcd-1234/*")
    )
    error_message = "the producer policy writes topics of this cluster only"
  }

  assert {
    condition     = output.client_settings.port == 9098 && output.client_settings.security_protocol == "SASL_SSL" && output.client_settings.sasl_mechanism == "OAUTHBEARER"
    error_message = "producers use SASL_SSL with IAM tokens on 9098"
  }
}

run "dev_size_is_accepted" {
  command = plan

  variables {
    env                 = "dev"
    broker_count        = 3
    instance_type       = "kafka.m7g.large"
    volume_size_gb      = 100
    enhanced_monitoring = "DEFAULT"
  }

  assert {
    condition     = aws_msk_cluster.this.number_of_broker_nodes == 3 && aws_msk_cluster.this.enhanced_monitoring == "DEFAULT"
    error_message = "dev runs three small brokers with default metrics"
  }
}

run "broker_count_stays_even_across_azs" {
  command = plan

  variables {
    broker_count = 7
  }

  expect_failures = [var.broker_count]
}

run "tag_schema_is_enforced" {
  command = plan

  variables {
    tags = { team = "data" }
  }

  expect_failures = [var.tags]
}

run "client_roles_only_with_a_client_cluster" {
  command = plan

  assert {
    condition     = length(aws_iam_role.client) == 0 && length(aws_eks_pod_identity_association.client) == 0
    error_message = "no client roles without a client cluster"
  }
}

run "clients_create_topics_or_read_lag_but_never_touch_data" {
  command = plan

  variables {
    client_cluster_name = "pay-prod-euc1-eks-analytics"
  }

  assert {
    condition     = aws_eks_pod_identity_association.client["topics"].namespace == "kafka-topics" && aws_eks_pod_identity_association.client["exporter"].service_account == "kafka-exporter"
    error_message = "the Job and the exporter get their roles through Pod Identity on their own service accounts"
  }
  assert {
    condition     = alltrue([for k, p in aws_iam_role_policy.client : !strcontains(p.policy, "ReadData") && !strcontains(p.policy, "WriteData") && !strcontains(p.policy, "AlterGroup")])
    error_message = "neither client reads or writes events"
  }
  assert {
    condition     = strcontains(aws_iam_role_policy.client["topics"].policy, "kafka-cluster:CreateTopic") && !strcontains(aws_iam_role_policy.client["exporter"].policy, "CreateTopic")
    error_message = "only the topics Job may create topics"
  }
}
