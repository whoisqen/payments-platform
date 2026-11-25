locals {
  msk_enabled     = var.msk_cluster_name != null
  msk_document    = "${local.env}-chaos-msk-reboot-broker"
  msk_cluster_arn = "arn:aws:kafka:${local.arn_base}:cluster/${coalesce(var.msk_cluster_name, "none")}/*"
}

# Name follows tests/chaos/fis/msk-broker-loss.json; the template passes a cluster name, RebootBroker needs the ARN.
resource "aws_ssm_document" "msk_reboot_broker" {
  count = local.msk_enabled ? 1 : 0

  name            = local.msk_document
  document_type   = "Automation"
  document_format = "YAML"
  content = yamlencode({
    schemaVersion = "0.3"
    description   = "Chaos: reboot one MSK broker and wait until the cluster is active again."
    assumeRole    = "{{ AutomationAssumeRole }}"
    parameters = {
      ClusterName          = { type = "String", allowedValues = [var.msk_cluster_name] }
      BrokerId             = { type = "String", allowedPattern = "^[0-9]{1,3}$" }
      AutomationAssumeRole = { type = "String", default = local.automation_role_arn }
    }
    mainSteps = [
      {
        name    = "FindCluster"
        action  = "aws:executeAwsApi"
        inputs  = { Service = "kafka", Api = "ListClustersV2", ClusterNameFilter = "{{ ClusterName }}" }
        outputs = [{ Name = "ClusterArn", Selector = "$.ClusterInfoList[0].ClusterArn", Type = "String" }]
      },
      {
        name   = "RebootBroker"
        action = "aws:executeAwsApi"
        inputs = { Service = "kafka", Api = "RebootBroker", ClusterArn = "{{ FindCluster.ClusterArn }}", BrokerIds = ["{{ BrokerId }}"] }
      },
      {
        # The state turns REBOOTING_BROKER asynchronously; waiting at once could read the old ACTIVE.
        name   = "LetRebootStart"
        action = "aws:sleep"
        inputs = { Duration = "PT1M" }
      },
      {
        name           = "WaitActive"
        action         = "aws:waitForAwsResourceProperty"
        timeoutSeconds = 840
        inputs = {
          Service          = "kafka"
          Api              = "DescribeClusterV2"
          ClusterArn       = "{{ FindCluster.ClusterArn }}"
          PropertySelector = "$.ClusterInfo.State"
          DesiredValues    = ["ACTIVE"]
        }
      },
    ]
  })
  tags = merge(var.tags, { Name = local.msk_document })
}

# The automation role belongs to fis-experiments; this policy is added once that role exists (EKS-style two-step apply).
resource "aws_iam_role_policy" "automation_msk" {
  count = local.msk_enabled && var.automation_role_exists ? 1 : 0

  name = "msk-reboot-broker"
  role = "${local.name}-chaos-automation"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "FindCluster"
        Effect   = "Allow"
        Action   = ["kafka:ListClustersV2"]
        Resource = "*"
      },
      {
        Sid      = "RebootTargetBroker"
        Effect   = "Allow"
        Action   = ["kafka:RebootBroker", "kafka:DescribeClusterV2"]
        Resource = local.msk_cluster_arn
      },
    ]
  })
}
