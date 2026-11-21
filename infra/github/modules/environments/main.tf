locals {
  environments = {
    dev      = []
    stage    = []
    prod     = [var.teams.sre]
    cde-prod = [var.teams.sre, var.teams.security]
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
