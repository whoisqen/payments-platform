mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::444444444444:role/mock" }
  }
}

variables {
  name_prefix              = "pay"
  environment              = "prod"
  account_id               = "444444444444"
  github_repository        = "example-org/payments-platform"
  regions                  = ["eu-central-1", "us-east-1"]
  permissions_boundary_arn = "arn:aws:iam::444444444444:policy/workload-boundary"
  tags = {
    team = "platform", owner = "platform@example.com", pci-scope = "connected", data-class = "internal", backup-tier = "none"
  }
}

run "names_match_runbook_py" {
  command = plan

  assert {
    condition     = aws_iam_role.caller["diagnose"].name == "pay-prod-glob-runbook-diagnose" && aws_iam_role.exec["actions"].name == "pay-prod-glob-runbook-actions-exec"
    error_message = "pay-<env>-glob-runbook-{diagnose,actions} and -exec"
  }
  assert {
    condition     = jsondecode(aws_iam_role.caller["actions"].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:example-org/payments-platform:environment:runbook-prod"
    error_message = "actions need the approval of the runbook-<env> environment"
  }
}

run "documents_are_limited_to_runbooks" {
  command = apply

  assert {
    condition = alltrue([for k, p in aws_iam_role_policy.caller : alltrue([for s in jsondecode(p.policy).Statement : alltrue([for r in s.Resource :
    strcontains(r, ":document/pay-runbook-") || strcontains(r, ":automation-definition/pay-runbook-") || strcontains(r, ":automation-execution/") || startswith(r, "arn:aws:iam::")])])])
    error_message = "only pay-runbook-* documents and their executions"
  }
}
