locals {
  name     = "${var.name_prefix}-${var.environment}-${var.region_short}"
  enabled  = var.environment != "prod" || var.allow_prod
  arn_base = "${var.region}:${var.account_id}"

  # Document name follows tests/chaos/fis/memorydb-failover.json (no region segment).
  memorydb_document = "${var.name_prefix}-${var.environment}-chaos-memorydb-failover-shard"
  memorydb_arn      = "arn:aws:memorydb:${local.arn_base}:cluster/${var.memorydb_cluster_name}"

  env_tag  = { environment = var.environment }
  cell_tag = merge(local.env_tag, { cell = var.target_cell })
  az_filter = [
    { path = "Placement.AvailabilityZone", values = [var.target_az] },
    { path = "State.Name", values = ["running"] },
  ]
  stop = "Stop: ${join(", ", [for a in var.stop_alarm_arns : element(split(":", a), 6)])} alarm."

  pod_target = var.eks_pod_actions == null ? null : {
    resource_type  = "aws:eks:pod"
    selection_mode = "PERCENT(${var.eks_pod_actions.percent})"
    tags           = {}
    filters        = []
    parameters = {
      clusterIdentifier          = var.eks_pod_actions.cluster_name
      namespace                  = var.eks_pod_actions.namespace
      selectorType               = "labelSelector"
      selectorValue              = var.eks_pod_actions.selector
      availabilityZoneIdentifier = var.target_az
    }
  }

  base_templates = {
    "az-loss" = {
      failure_mode = "compute-az-loss"
      description  = "Hypothesis: with ${var.target_az} unreachable the cells keep the SLOs on two AZs (confirm 5xx below 0.01%, overhead p99 below 150 ms) and RTO is 1 min."
      targets = {
        "az-subnets" = { resource_type = "aws:ec2:subnet", selection_mode = "ALL", tags = merge(local.env_tag, { component = "vpc" }), filters = [{ path = "AvailabilityZone", values = [var.target_az] }], parameters = {} }
      }
      actions = {
        "disrupt-az" = { action_id = "aws:network:disrupt-connectivity", description = "Block all traffic of the subnets of one AZ", parameters = { scope = "all", duration = var.disruption_duration }, targets = { Subnets = "az-subnets" } }
      }
    }
    "node-loss" = {
      failure_mode = "compute-node-notready"
      description  = "Hypothesis: losing ${var.node_selection_mode} ${var.node_pool} nodes in ${var.target_az} leaves PDB and anti-affinity intact, Karpenter replaces them and the SLOs hold."
      targets = {
        "pool-nodes" = { resource_type = "aws:ec2:instance", selection_mode = var.node_selection_mode, tags = merge(local.cell_tag, { "karpenter.sh/nodepool" = var.node_pool }), filters = local.az_filter, parameters = {} }
      }
      actions = {
        "terminate-nodes" = { action_id = "aws:ec2:terminate-instances", description = "Terminate nodes of the pool in one AZ", parameters = {}, targets = { Instances = "pool-nodes" } }
      }
    }
    "workers-spot-interruption" = {
      failure_mode = "compute-spot-interruption"
      description  = "Hypothesis: when every spot node of ${var.spot_node_pool} in ${var.target_az} is interrupted, drainer and scheduler consumer move and drain lag stays below 30 s."
      targets = {
        "spot-nodes" = { resource_type = "aws:ec2:spot-instance", selection_mode = "ALL", tags = merge(local.cell_tag, { "karpenter.sh/nodepool" = var.spot_node_pool }), filters = local.az_filter, parameters = {} }
      }
      actions = {
        "interrupt-spot" = { action_id = "aws:ec2:send-spot-instance-interruptions", description = "Two-minute interruption notice to spot nodes of one AZ", parameters = { durationBeforeInterruption = "PT2M" }, targets = { SpotInstances = "spot-nodes" } }
      }
    }
    "aurora-writer-failover" = {
      failure_mode = "data-aurora-writer-failover"
      description  = "Hypothesis: an Aurora writer failover of ${var.target_cell} is invisible on the hot path (write-behind), the Redis stream grows and returns below 5,000 within 2 min with no loss."
      targets = {
        "cell-aurora" = { resource_type = "aws:rds:cluster", selection_mode = "ALL", tags = merge(local.cell_tag, { component = "aurora" }), filters = [], parameters = {} }
      }
      actions = {
        "failover-writer" = { action_id = "aws:rds:failover-db-cluster", description = "Promote a reader of the cell cluster to writer", parameters = {}, targets = { Clusters = "cell-aurora" } }
      }
    }
    "memorydb-failover" = {
      failure_mode = "data-memorydb-failover"
      description  = "Hypothesis: a MemoryDB shard failover of ${var.target_cell} loses no payment writes and keeps 5xx below 0.1% for at most 30 s. FIS has no MemoryDB action: SSM Automation calls FailoverShard."
      targets      = {}
      actions = {
        "failover-shard" = {
          action_id   = "aws:ssm:send-automation-document"
          description = "Run FailoverShard on one shard of the cell cluster"
          parameters = {
            documentArn        = aws_ssm_document.memorydb_failover.arn
            documentParameters = jsonencode({ ClusterName = var.memorydb_cluster_name, ShardName = var.memorydb_shard_name, AutomationAssumeRole = aws_iam_role.automation.arn })
            maxDuration        = "PT10M"
          }
          targets = {}
        }
      }
    }
  }

  pod_templates = var.eks_pod_actions == null ? {} : {
    "pod-loss" = {
      failure_mode = "compute-pod-loss"
      description  = "Hypothesis: deleting ${var.eks_pod_actions.percent}% of ${var.eks_pod_actions.selector} pods in ${var.target_az} keeps the SLOs; replicas in the other AZs take the traffic."
      targets      = { "az-pods" = local.pod_target }
      actions = {
        "delete-pods" = { action_id = "aws:eks:pod-delete", description = "Delete pods of one AZ", parameters = { kubernetesServiceAccount = var.eks_pod_actions.service_account }, targets = { Pods = "az-pods" } }
      }
    }
  }

  latency_templates = var.psp_latency == null || var.eks_pod_actions == null ? {} : {
    "psp-egress-latency" = {
      failure_mode = "psp-latency"
      description  = "Hypothesis: ${var.psp_latency.delay_ms} ms extra on PSP egress opens no double charge; timeouts end as unknown and are synced by the scheduler, other PSPs are unaffected."
      targets = {
        "egress-pods" = merge(local.pod_target, {
          selection_mode = "PERCENT(${var.psp_latency.pod_percent})"
          parameters     = merge(local.pod_target.parameters, { namespace = var.psp_latency.namespace, selectorValue = var.psp_latency.selector })
        })
      }
      actions = {
        "psp-latency" = {
          action_id   = "aws:eks:pod-network-latency"
          description = "Delay traffic of the egress pods to the PSP destinations"
          parameters = {
            kubernetesServiceAccount = var.eks_pod_actions.service_account
            delayMilliseconds        = tostring(var.psp_latency.delay_ms)
            jitterMilliseconds       = tostring(var.psp_latency.jitter_ms)
            sources                  = join(",", var.psp_latency.destinations)
            duration                 = var.psp_latency.duration
          }
          targets = { Pods = "egress-pods" }
        }
      }
    }
  }

  templates = local.enabled ? merge(local.base_templates, local.pod_templates, local.latency_templates) : {}
}

resource "aws_cloudwatch_log_group" "fis" {
  name              = "/fis/${local.name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.log_kms_key_arn
  tags              = merge(var.tags, { Name = "/fis/${local.name}" })
}

resource "aws_iam_role" "fis" {
  name                 = "${local.name}-fis-experiment"
  permissions_boundary = var.permissions_boundary_arn
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "fis.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = var.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:aws:fis:${local.arn_base}:experiment/*" }
      }
    }]
  })
  tags = merge(var.tags, { Name = "${local.name}-fis-experiment" })
}

# Destructive actions reach only resources tagged with this environment; network ACLs are the ones FIS creates and tags itself.
resource "aws_iam_role_policy" "fis" {
  name = "fis-experiments"
  role = aws_iam_role.fis.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid       = "NodesOfThisEnvironment"
        Effect    = "Allow"
        Action    = ["ec2:TerminateInstances", "ec2:SendSpotInstanceInterruptions"]
        Resource  = "arn:aws:ec2:${local.arn_base}:instance/*"
        Condition = { StringEquals = { "aws:ResourceTag/environment" = var.environment } }
      },
      {
        Sid       = "AuroraOfThisEnvironment"
        Effect    = "Allow"
        Action    = ["rds:FailoverDBCluster"]
        Resource  = "arn:aws:rds:${local.arn_base}:cluster:*"
        Condition = { StringEquals = { "aws:ResourceTag/environment" = var.environment } }
      },
      {
        Sid       = "CreateFisNetworkAcl"
        Effect    = "Allow"
        Action    = ["ec2:CreateNetworkAcl"]
        Resource  = "arn:aws:ec2:${local.arn_base}:network-acl/*"
        Condition = { StringEquals = { "aws:RequestTag/managedByFIS" = "true" } }
      },
      {
        Sid       = "CreateFisNetworkAclInVpc"
        Effect    = "Allow"
        Action    = ["ec2:CreateNetworkAcl"]
        Resource  = "arn:aws:ec2:${local.arn_base}:vpc/*"
        Condition = { StringEquals = { "aws:ResourceTag/environment" = var.environment } }
      },
      {
        Sid       = "TagFisNetworkAcl"
        Effect    = "Allow"
        Action    = ["ec2:CreateTags"]
        Resource  = "arn:aws:ec2:${local.arn_base}:network-acl/*"
        Condition = { StringEquals = { "ec2:CreateAction" = "CreateNetworkAcl" } }
      },
      {
        Sid       = "ManageFisNetworkAcl"
        Effect    = "Allow"
        Action    = ["ec2:CreateNetworkAclEntry", "ec2:DeleteNetworkAcl"]
        Resource  = "arn:aws:ec2:${local.arn_base}:network-acl/*"
        Condition = { StringEquals = { "aws:ResourceTag/managedByFIS" = "true" } }
      },
      {
        Sid       = "SwapAclOfSubnetsOfThisEnvironment"
        Effect    = "Allow"
        Action    = ["ec2:ReplaceNetworkAclAssociation"]
        Resource  = "arn:aws:ec2:${local.arn_base}:subnet/*"
        Condition = { StringEquals = { "aws:ResourceTag/environment" = var.environment } }
      },
      {
        Sid      = "SwapAclAssociation"
        Effect   = "Allow"
        Action   = ["ec2:ReplaceNetworkAclAssociation"]
        Resource = "arn:aws:ec2:${local.arn_base}:network-acl/*"
      },
      {
        Sid    = "ResolveTargets"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances", "ec2:DescribeSubnets", "ec2:DescribeNetworkAcls", "ec2:DescribeVpcs", "ec2:DescribeManagedPrefixLists",
          "ec2:GetManagedPrefixListEntries", "ec2:DescribeVpcPeeringConnections", "ec2:DescribeTransitGatewayAttachments",
          "ec2:DescribeVpcEndpoints", "rds:DescribeDBClusters", "tag:GetResources",
        ]
        Resource = "*"
      },
      {
        Sid      = "StartMemoryDbFailover"
        Effect   = "Allow"
        Action   = ["ssm:StartAutomationExecution"]
        Resource = [aws_ssm_document.memorydb_failover.arn, "arn:aws:ssm:${local.arn_base}:automation-definition/${local.memorydb_document}:*"]
      },
      {
        Sid      = "FollowAutomation"
        Effect   = "Allow"
        Action   = ["ssm:GetAutomationExecution", "ssm:StopAutomationExecution"]
        Resource = "arn:aws:ssm:${local.arn_base}:automation-execution/*"
      },
      {
        Sid       = "PassAutomationRole"
        Effect    = "Allow"
        Action    = ["iam:PassRole"]
        Resource  = aws_iam_role.automation.arn
        Condition = { StringEquals = { "iam:PassedToService" = "ssm.amazonaws.com" } }
      },
      {
        Sid      = "ExperimentLogDelivery"
        Effect   = "Allow"
        Action   = ["logs:CreateLogDelivery", "logs:PutResourcePolicy", "logs:DescribeResourcePolicies", "logs:DescribeLogGroups"]
        Resource = "*"
      },
      ], var.eks_pod_actions == null ? [] : [{
        Sid      = "DescribeTargetCluster"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = "arn:aws:eks:${local.arn_base}:cluster/${var.eks_pod_actions.cluster_name}"
    }])
  })
}

resource "aws_iam_role" "automation" {
  name                 = "${local.name}-chaos-automation"
  permissions_boundary = var.permissions_boundary_arn
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ssm.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = var.account_id } }
    }]
  })
  tags = merge(var.tags, { Name = "${local.name}-chaos-automation" })
}

resource "aws_iam_role_policy" "automation" {
  name = "memorydb-failover"
  role = aws_iam_role.automation.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "FailoverTargetCluster"
      Effect   = "Allow"
      Action   = ["memorydb:FailoverShard", "memorydb:DescribeClusters"]
      Resource = local.memorydb_arn
    }]
  })
}

resource "aws_ssm_document" "memorydb_failover" {
  name            = local.memorydb_document
  document_type   = "Automation"
  document_format = "YAML"
  content = yamlencode({
    schemaVersion = "0.3"
    description   = "Chaos: fail over one MemoryDB shard and wait until the cluster is available again."
    assumeRole    = "{{ AutomationAssumeRole }}"
    parameters = {
      ClusterName          = { type = "String" }
      ShardName            = { type = "String" }
      AutomationAssumeRole = { type = "String" }
    }
    mainSteps = [
      {
        name   = "FailoverShard"
        action = "aws:executeAwsApi"
        inputs = { Service = "memorydb", Api = "FailoverShard", ClusterName = "{{ ClusterName }}", ShardName = "{{ ShardName }}" }
      },
      {
        name           = "WaitAvailable"
        action         = "aws:waitForAwsResourceProperty"
        timeoutSeconds = 600
        inputs = {
          Service          = "memorydb"
          Api              = "DescribeClusters"
          ClusterName      = "{{ ClusterName }}"
          PropertySelector = "$.Clusters[0].Status"
          DesiredValues    = ["available"]
        }
      },
    ]
  })
  tags = merge(var.tags, { Name = local.memorydb_document })
}

resource "aws_fis_experiment_template" "this" {
  for_each = local.templates

  description = substr("${each.value.description} ${local.stop}", 0, 512)
  role_arn    = aws_iam_role.fis.arn

  dynamic "stop_condition" {
    for_each = toset(var.stop_alarm_arns)
    content {
      source = "aws:cloudwatch:alarm"
      value  = stop_condition.value
    }
  }

  dynamic "target" {
    for_each = each.value.targets
    content {
      name           = target.key
      resource_type  = target.value.resource_type
      selection_mode = target.value.selection_mode
      parameters     = length(target.value.parameters) > 0 ? target.value.parameters : null

      dynamic "resource_tag" {
        for_each = target.value.tags
        content {
          key   = resource_tag.key
          value = resource_tag.value
        }
      }

      dynamic "filter" {
        for_each = target.value.filters
        content {
          path   = filter.value.path
          values = filter.value.values
        }
      }
    }
  }

  dynamic "action" {
    for_each = each.value.actions
    content {
      name        = action.key
      action_id   = action.value.action_id
      description = action.value.description

      dynamic "parameter" {
        for_each = action.value.parameters
        content {
          key   = parameter.key
          value = parameter.value
        }
      }

      dynamic "target" {
        for_each = action.value.targets
        content {
          key   = target.key
          value = target.value
        }
      }
    }
  }

  log_configuration {
    log_schema_version = 2
    cloudwatch_logs_configuration {
      log_group_arn = "${aws_cloudwatch_log_group.fis.arn}:*"
    }
  }

  experiment_options {
    account_targeting            = "single-account"
    empty_target_resolution_mode = "fail"
  }

  tags = merge(var.tags, { Name = "chaos-${each.key}", "failure-mode" = each.value.failure_mode })
}
