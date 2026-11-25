mock_provider "aws" {
  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::222222222222:policy/fis-experiment-boundary"
    }
  }
  mock_resource "aws_cloudwatch_composite_alarm" {
    defaults = {
      arn = "arn:aws:cloudwatch:eu-central-1:222222222222:alarm:pay-stage-euc1-chaos-stop"
    }
  }
}

variables {
  name_prefix  = "pay"
  environment  = "stage"
  region       = "eu-central-1"
  region_short = "euc1"
  account_id   = "222222222222"
  tags = {
    team          = "platform"
    owner         = "platform@example.com"
    "pci-scope"   = "connected"
    "data-class"  = "internal"
    "backup-tier" = "none"
  }
}

run "defaults" {
  command = plan

  assert {
    condition     = aws_iam_policy.boundary.name == "fis-experiment-boundary" && aws_iam_policy.boundary.path == "/"
    error_message = "The boundary must keep the name fis-experiments falls back to."
  }

  assert {
    condition     = aws_cloudwatch_composite_alarm.chaos_stop.alarm_name == "pay-stage-euc1-chaos-stop"
    error_message = "The composite alarm must keep the name fis-experiments falls back to."
  }

  assert {
    condition     = aws_cloudwatch_composite_alarm.chaos_stop.alarm_rule == "ALARM(\"pay-stage-euc1-chaos-stop-slo\")"
    error_message = "Without edge or Aurora inputs the rule is the SLO stop signal only."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.stop_signal.treat_missing_data == "breaching" && aws_cloudwatch_metric_alarm.stop_signal.dimensions["Environment"] == "stage"
    error_message = "A silent bridge must block experiments."
  }

  assert {
    condition     = length(aws_eks_access_entry.fis) == 0 && output.fis_access_entry_username == null && length(aws_ssm_document.msk_reboot_broker) == 0 && length(aws_iam_role_policy.automation_msk) == 0
    error_message = "No access entry before the FIS role exists."
  }
}

run "boundary_covers_role_policies" {
  command = plan

  variables {
    # Every action of the fis and automation inline policies of fis-experiments.
    role_actions = [
      "ec2:TerminateInstances", "ec2:SendSpotInstanceInterruptions", "rds:FailoverDBCluster",
      "ec2:CreateNetworkAcl", "ec2:CreateTags", "ec2:CreateNetworkAclEntry", "ec2:DeleteNetworkAcl", "ec2:ReplaceNetworkAclAssociation",
      "ec2:DescribeInstances", "ec2:DescribeSubnets", "ec2:DescribeNetworkAcls", "ec2:DescribeVpcs", "ec2:DescribeManagedPrefixLists",
      "ec2:GetManagedPrefixListEntries", "ec2:DescribeVpcPeeringConnections", "ec2:DescribeTransitGatewayAttachments",
      "ec2:DescribeVpcEndpoints", "rds:DescribeDBClusters", "tag:GetResources",
      "ssm:StartAutomationExecution", "ssm:GetAutomationExecution", "ssm:StopAutomationExecution", "iam:PassRole",
      "logs:CreateLogDelivery", "logs:PutResourcePolicy", "logs:DescribeResourcePolicies", "logs:DescribeLogGroups",
      "eks:DescribeCluster", "memorydb:FailoverShard", "memorydb:DescribeClusters", "ssm:SendCommand", "ec2:StopInstances",
      "kafka:RebootBroker", "kafka:DescribeClusterV2", "kafka:ListClustersV2",
    ]
  }

  assert {
    condition = alltrue([
      for a in var.role_actions : contains(flatten([for s in jsondecode(aws_iam_policy.boundary.policy).Statement : s.Action]), a)
    ])
    error_message = "The boundary misses an action of the fis-experiments role policies."
  }

  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_policy.boundary.policy).Statement : s.Effect == "Allow" && !contains(flatten([s.Action]), "*")
    ])
    error_message = "The boundary allows explicit actions only."
  }

  assert {
    condition     = length(aws_iam_policy.boundary.policy) <= 6144
    error_message = "The boundary exceeds the 6,144-character limit of a managed policy."
  }

  assert {
    condition = contains(
      flatten([for s in jsondecode(aws_iam_policy.boundary.policy).Statement : s.Resource if s.Sid == "StartChaosAutomation"]),
      "arn:aws:ssm:eu-central-1:222222222222:document/pay-stage-chaos-*"
    ) && one([for s in jsondecode(aws_iam_policy.boundary.policy).Statement : s.Resource if s.Sid == "PassAutomationRole"]) == "arn:aws:iam::222222222222:role/pay-stage-euc1-chaos-automation"
    error_message = "SSM and PassRole must match the document and role names of fis-experiments."
  }

  assert {
    condition     = one([for s in jsondecode(aws_iam_policy.boundary.policy).Statement : s.Condition if s.Sid == "ManageFisNetworkAcl"]).StringEquals["aws:ResourceTag/managedByFIS"] == "true"
    error_message = "Network ACL changes are limited to the ACLs FIS creates."
  }
}

run "children_and_access_entry" {
  command = plan

  variables {
    edge_target_groups     = [{ key = "payments", load_balancer = "net/k8s-payments-edge/abc", target_group = "targetgroup/k8s-payments-edge/def", min_healthy = 2 }]
    aurora_cluster_ids     = ["pay-stage-euc1-aurora-cell-1"]
    additional_alarm_arns  = ["arn:aws:cloudwatch:eu-central-1:222222222222:alarm:pay-stage-euc1-auth-rate"]
    eks_access_entry       = { cluster_name = "pay-stage-euc1-eks" }
    alarm_actions          = ["arn:aws:sns:eu-central-1:222222222222:chaos"]
    msk_cluster_name       = "pay-stage-euc1-msk"
    automation_role_exists = true
  }

  assert {
    condition     = aws_ssm_document.msk_reboot_broker[0].name == "pay-stage-chaos-msk-reboot-broker" && yamldecode(aws_ssm_document.msk_reboot_broker[0].content).parameters.ClusterName.allowedValues == ["pay-stage-euc1-msk"]
    error_message = "The reboot document keeps the name of tests/chaos/fis/msk-broker-loss.json and accepts only the environment cluster."
  }

  assert {
    condition     = aws_iam_role_policy.automation_msk[0].role == "pay-stage-euc1-chaos-automation" && strcontains(aws_iam_role_policy.automation_msk[0].policy, "arn:aws:kafka:eu-central-1:222222222222:cluster/pay-stage-euc1-msk/*")
    error_message = "The automation role may reboot only the environment MSK cluster."
  }

  assert {
    condition     = length(local.child_alarm_names) == 4 && strcontains(aws_cloudwatch_composite_alarm.chaos_stop.alarm_rule, "ALARM(\"arn:aws:cloudwatch:eu-central-1:222222222222:alarm:pay-stage-euc1-auth-rate\")")
    error_message = "The composite must OR every child alarm."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.edge_healthy["payments"].evaluation_periods == 3 && aws_cloudwatch_metric_alarm.edge_healthy["payments"].treat_missing_data == "notBreaching"
    error_message = "Edge capacity must be sustained over 3 min to outlast the az-loss reroute."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.aurora_writer["pay-stage-euc1-aurora-cell-1"].evaluation_periods == 5 && aws_cloudwatch_metric_alarm.aurora_writer["pay-stage-euc1-aurora-cell-1"].dimensions["Role"] == "WRITER"
    error_message = "Aurora writer loss must outlast the 2 min failover hypothesis."
  }

  assert {
    condition     = aws_eks_access_entry.fis[0].principal_arn == "arn:aws:iam::222222222222:role/pay-stage-euc1-fis-experiment" && aws_eks_access_entry.fis[0].user_name == "fis-experiment" && aws_eks_access_entry.fis[0].type == "STANDARD"
    error_message = "The access entry maps the fis-experiments role to the fis-experiment user."
  }

  assert {
    condition     = aws_cloudwatch_composite_alarm.chaos_stop.actions_enabled
    error_message = "Alarm actions must be enabled when topics are given."
  }
}

run "rejects_short_aurora_window" {
  command = plan

  variables {
    aurora_writer_minutes = 2
  }

  expect_failures = [var.aurora_writer_minutes]
}

run "rejects_alb_suffix" {
  command = plan

  variables {
    edge_target_groups = [{ key = "x", load_balancer = "app/x/1", target_group = "targetgroup/x/2", min_healthy = 1 }]
  }

  expect_failures = [var.edge_target_groups]
}
