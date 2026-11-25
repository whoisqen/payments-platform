mock_provider "aws" {}

variables {
  name_prefix                     = "pay"
  region                          = "eu-central-1"
  environment                     = "dev"
  cell                            = "cell-0"
  account_id                      = "111111111111"
  cluster_name                    = "pay-dev-euc1-eks-cell-0"
  cluster_arn                     = "arn:aws:eks:eu-central-1:111111111111:cluster/pay-dev-euc1-eks-cell-0"
  permissions_boundary_arn        = "arn:aws:iam::111111111111:policy/workload-boundary"
  deny_recovery_writes_policy_arn = "arn:aws:iam::111111111111:policy/deny-recovery-writes"
  memorydb = {
    cluster_arn = "arn:aws:memorydb:eu-central-1:111111111111:cluster/pay-dev-euc1-memorydb-cell-0"
    users       = { router = "router", drainer = "drainer", scheduler = "scheduler" }
  }
  rds_db_connect_arns = {
    router    = ["arn:aws:rds-db:eu-central-1:111111111111:dbuser:prx-0aaa/router"]
    locker    = ["arn:aws:rds-db:eu-central-1:111111111111:dbuser:prx-0bbb/locker"]
    drainer   = ["arn:aws:rds-db:eu-central-1:111111111111:dbuser:prx-0aaa/drainer"]
    scheduler = ["arn:aws:rds-db:eu-central-1:111111111111:dbuser:prx-0aaa/scheduler"]
  }
  locker_kms_key_arn  = "arn:aws:kms:eu-central-1:111111111111:key/locker"
  secrets_kms_key_arn = "arn:aws:kms:eu-central-1:111111111111:key/secrets"
  secret_arns         = ["arn:aws:secretsmanager:eu-central-1:111111111111:secret:pay/dev/router-AbCdEf"]
  dynamodb_table_arn  = "arn:aws:dynamodb:eu-central-1:111111111111:table/merchant-cell-map"
  tags = {
    team = "payments-core", owner = "payments@example.com", pci-scope = "cde", data-class = "card-data", backup-tier = "gold"
  }
}

run "five_roles_with_boundary_and_deny_policy" {
  command = plan

  assert {
    condition     = length(aws_iam_role.this) == 5 && alltrue([for r in aws_iam_role.this : r.permissions_boundary == var.permissions_boundary_arn])
    error_message = "five roles, each with the boundary"
  }
  assert {
    condition     = length(aws_iam_role_policy_attachment.deny_recovery_writes) == 5
    error_message = "every role attaches the deny recovery writes policy"
  }
  assert {
    condition     = aws_iam_role.this["locker"].name == "pay-dev-euc1-cell-0-locker"
    error_message = "role names follow pay-<env>-<region-short>-<cell>-<service>"
  }
}

run "trust_is_pod_identity_of_this_cluster" {
  command = plan

  assert {
    condition     = jsondecode(aws_iam_role.this["router"].assume_role_policy).Statement[0].Principal.Service == "pods.eks.amazonaws.com"
    error_message = "trust is the pod identity service"
  }
  assert {
    condition     = jsondecode(aws_iam_role.this["router"].assume_role_policy).Statement[0].Action == ["sts:AssumeRole", "sts:TagSession"]
    error_message = "trust allows AssumeRole and TagSession"
  }
  assert {
    condition     = jsondecode(aws_iam_role.this["router"].assume_role_policy).Statement[0].Condition.ArnEquals["aws:SourceArn"] == var.cluster_arn
    error_message = "only pods of this cluster may assume the role"
  }
}

run "no_wildcard_in_any_policy" {
  command = plan

  assert {
    condition     = alltrue([for k, p in aws_iam_role_policy.this : !strcontains(p.policy, "*")])
    error_message = "a policy contains a wildcard in an action or resource"
  }
}

run "only_locker_uses_the_locker_key" {
  command = plan

  assert {
    condition     = strcontains(aws_iam_role_policy.this["locker"].policy, var.locker_kms_key_arn)
    error_message = "locker must use its key"
  }
  assert {
    condition     = alltrue([for k, p in aws_iam_role_policy.this : !strcontains(p.policy, var.locker_kms_key_arn) if k != "locker"])
    error_message = "no other role may touch the locker key"
  }
}

run "router_cannot_read_secrets_and_locker_has_no_cache_access" {
  command = plan

  assert {
    condition     = !strcontains(aws_iam_role_policy.this["router"].policy, "secretsmanager") && !strcontains(aws_iam_role_policy.this["locker"].policy, "memorydb")
    error_message = "access follows the service duty"
  }
  assert {
    condition     = strcontains(aws_iam_role_policy.this["external-secrets"].policy, "secretsmanager:GetSecretValue") && strcontains(aws_iam_role_policy.this["external-secrets"].policy, "secretsmanager.eu-central-1.amazonaws.com")
    error_message = "external-secrets reads listed secrets through Secrets Manager only"
  }
}

run "merchant_map_is_read_only" {
  command = plan

  assert {
    condition     = !strcontains(aws_iam_role_policy.this["router"].policy, "dynamodb:PutItem") && !strcontains(aws_iam_role_policy.this["router"].policy, "dynamodb:UpdateItem")
    error_message = "cells never write the merchant map"
  }
}

run "yace_reads_cloudwatch_only" {
  command = plan

  assert {
    condition = (
      aws_iam_role.yace[0].name == "pay-dev-euc1-cell-0-yace" &&
      aws_iam_role.yace[0].permissions_boundary == var.permissions_boundary_arn &&
      jsondecode(aws_iam_role.yace[0].assume_role_policy).Statement[0].Condition.ArnEquals["aws:SourceArn"] == var.cluster_arn
    )
    error_message = "the yace role is a pod identity role of this cluster with the boundary"
  }
  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_role_policy.yace[0].policy).Statement :
      s.Effect == "Allow" && alltrue([for a in s.Action : contains(["cloudwatch:GetMetricData", "cloudwatch:GetMetricStatistics", "cloudwatch:ListMetrics", "tag:GetResources"], a)])
    ])
    error_message = "yace may only read metrics and discover tagged resources"
  }
  assert {
    condition     = aws_eks_pod_identity_association.yace[0].namespace == "monitoring" && aws_eks_pod_identity_association.yace[0].service_account == "yace"
    error_message = "associated with monitoring/yace"
  }
}

run "yace_can_be_turned_off" {
  command = plan

  variables {
    yace = { enabled = false }
  }

  assert {
    condition     = length(aws_iam_role.yace) == 0 && length(aws_eks_pod_identity_association.yace) == 0
    error_message = "no exporter role when disabled"
  }
}

run "only_producers_get_the_msk_policy" {
  command = plan

  variables {
    kafka_producer_policy_arn = "arn:aws:iam::111111111111:policy/pay-dev-euc1-msk-producer"
  }

  assert {
    condition     = toset(keys(aws_iam_role_policy_attachment.kafka_producer)) == toset(["router", "scheduler"])
    error_message = "router and scheduler publish events, the locker does not"
  }
}

run "locker_cannot_be_a_producer" {
  command = plan

  variables {
    kafka_producer_policy_arn = "arn:aws:iam::111111111111:policy/pay-dev-euc1-msk-producer"
    kafka_producers           = ["router", "locker"]
  }

  expect_failures = [var.kafka_producers]
}
