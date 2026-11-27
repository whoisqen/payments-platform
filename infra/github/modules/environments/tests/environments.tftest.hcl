mock_provider "github" {
  mock_data "github_team" {
    defaults = {
      id = "1"
    }
  }
}

variables {
  repository = "payments-platform"
  branch     = "main"
  reviewers  = true
  teams = {
    payments_core = "pc"
    security      = "sec"
    platform      = "plat"
    sre           = "sre"
  }
}

run "environments" {
  command = plan

  assert {
    condition     = toset(keys(github_repository_environment.this)) == toset(["dev", "stage", "prod", "cde-prod", "management", "security", "shared-services", "runbook-dev", "runbook-stage", "runbook-prod"])
    error_message = "the workload environments, the organization state roots and the runbook approvals exist"
  }
  assert {
    condition     = length(local.environments["cde-prod"]) == 2 && length(local.environments["prod"]) == 1 && length(local.environments["dev"]) == 0
    error_message = "cde-prod needs sre and security, prod needs sre, dev none"
  }
  assert {
    condition     = alltrue([for e in github_repository_environment_deployment_policy.main_only : e.branch_pattern == "main"])
    error_message = "environments deploy from main only"
  }
}
