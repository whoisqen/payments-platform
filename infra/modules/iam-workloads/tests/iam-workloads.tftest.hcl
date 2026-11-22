mock_provider "aws" {}

variables {
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
