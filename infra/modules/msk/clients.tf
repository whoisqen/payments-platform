# Pod Identity roles of the two platform clients that run in the cluster next to MSK (client_cluster_name):
# the kafka-topics Job creates the event topics, the kafka-exporter reads lag and partitions. Neither reads or writes data.
locals {
  clients = var.client_cluster_name == null ? {} : {
    topics = {
      namespace       = "kafka-topics"
      service_account = "kafka-topics"
      actions_cluster = ["kafka-cluster:Connect", "kafka-cluster:DescribeCluster"]
      actions_topic   = ["kafka-cluster:CreateTopic", "kafka-cluster:DescribeTopic", "kafka-cluster:DescribeTopicDynamicConfiguration"]
      actions_group   = []
    }
    exporter = {
      namespace       = "monitoring"
      service_account = "kafka-exporter"
      actions_cluster = ["kafka-cluster:Connect", "kafka-cluster:DescribeCluster"]
      actions_topic   = ["kafka-cluster:DescribeTopic"]
      actions_group   = ["kafka-cluster:DescribeGroup"]
    }
  }
}

resource "aws_iam_role" "client" {
  for_each = local.clients

  name = "${local.name}-${each.key}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Condition = { StringEquals = { "aws:SourceAccount" = var.account_id } }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "client" {
  for_each = local.clients

  name = "msk-${each.key}"
  role = aws_iam_role.client[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        { Effect = "Allow", Action = each.value.actions_cluster, Resource = [local.cluster_arn] },
        { Effect = "Allow", Action = each.value.actions_topic, Resource = [local.topic_arn] },
      ],
      length(each.value.actions_group) == 0 ? [] : [{ Effect = "Allow", Action = each.value.actions_group, Resource = [local.group_arn] }],
    )
  })
}

resource "aws_eks_pod_identity_association" "client" {
  for_each = local.clients

  cluster_name    = var.client_cluster_name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = aws_iam_role.client[each.key].arn

  tags = var.tags
}
