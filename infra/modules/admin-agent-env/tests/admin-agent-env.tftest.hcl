mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::444444444444:role/pay-prod-admin-agent" }
  }
}

variables {
  name_prefix              = "pay"
  environment              = "prod"
  account_id               = "444444444444"
  region                   = "eu-central-1"
  admin_role_arn           = "arn:aws:iam::222222222222:role/pay-shared-bedrock-admin-agent"
  opensearch_domain_arn    = "arn:aws:es:eu-central-1:222222222222:domain/pay-shared-euc1-logs"
  log_group_names          = ["/payments/prod/application"]
  clusters                 = { "pay-prod-euc1-eks-control-center" = { namespaces = ["control-center"] } }
  permissions_boundary_arn = "arn:aws:iam::444444444444:policy/workload-boundary"
  tags                     = { team = "platform", owner = "platform@example.com", pci-scope = "connected", data-class = "internal", backup-tier = "none" }
}

run "only_the_bedrock_admin_role_assumes_it" {
  command = plan

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Principal.AWS == var.admin_role_arn
    error_message = "the shared-services admin agent role is the only principal"
  }
}

run "reads_only_its_own_log_stream_and_never_secrets" {
  command = plan

  assert {
    condition     = one([for s in jsondecode(aws_iam_role_policy.this.policy).Statement : s.Resource if s.Sid == "SearchLogs"]) == ["arn:aws:es:eu-central-1:222222222222:domain/pay-shared-euc1-logs/logs-app-prod/_search"]
    error_message = "search on logs-app-<env> only"
  }
  assert {
    condition     = contains(one([for s in jsondecode(aws_iam_role_policy.this.policy).Statement : s.Action if s.Sid == "DenySecretsAndKeys"]), "secretsmanager:*")
    error_message = "secrets and keys are denied"
  }
  assert {
    condition     = aws_eks_access_policy_association.this["pay-prod-euc1-eks-control-center"].access_scope[0].type == "namespace"
    error_message = "kubectl view is namespace-scoped"
  }
}

run "cluster_wide_view_is_rejected" {
  command = plan

  variables {
    clusters = { "pay-prod-euc1-eks-cell-0" = { namespaces = [] } }
  }

  expect_failures = [var.clusters]
}
