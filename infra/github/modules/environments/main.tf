locals {
  environments = {
    dev      = []
    stage    = []
    prod     = var.reviewers ? [var.teams.sre] : []
    cde-prod = var.reviewers ? [var.teams.sre, var.teams.security] : []
    # State roots of the organization accounts: their apply roles trust environment:<root>.
    management        = var.reviewers ? [var.teams.sre, var.teams.security] : []
    security          = var.reviewers ? [var.teams.sre, var.teams.security] : []
    "shared-services" = var.reviewers ? [var.teams.sre] : []
    # runbook-actions.yml runs the write steps of a runbook after the approval of runbook-<env>.
    runbook-dev   = []
    runbook-stage = var.reviewers ? [var.teams.sre] : []
    runbook-prod  = var.reviewers ? [var.teams.sre] : []
  }
}

data "github_team" "reviewer" {
  for_each = toset(distinct(flatten(values(local.environments))))
  slug     = each.value
}

resource "github_repository_environment" "this" {
  for_each    = local.environments
  repository  = var.repository
  environment = each.key

  dynamic "reviewers" {
    for_each = length(each.value) > 0 ? [1] : []
    content {
      teams = [for slug in each.value : data.github_team.reviewer[slug].id]
    }
  }

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "main_only" {
  for_each       = local.environments
  repository     = var.repository
  environment    = github_repository_environment.this[each.key].environment
  branch_pattern = var.branch
}
