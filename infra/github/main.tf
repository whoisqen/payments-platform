module "organization" {
  count         = var.account_type == "organization" ? 1 : 0
  source        = "./modules/organization"
  billing_email = var.billing_email
}

module "repository" {
  source             = "./modules/repository"
  name               = var.repository
  description        = var.repository_description
  visibility         = var.visibility
  allow_squash_merge = var.allow_squash_merge
  allow_rebase_merge = var.allow_rebase_merge
  allowed_actions    = var.allowed_actions
}

module "rulesets" {
  source             = "./modules/rulesets"
  repository         = module.repository.name
  required_checks    = var.required_checks
  approvals          = var.main_approvals
  tag_bypass         = var.tag_bypass
  merge_queue        = var.account_type == "organization"
  main_admin_bypass  = var.account_type == "user"
  require_signatures = var.require_signatures
}

module "environments" {
  source     = "./modules/environments"
  repository = module.repository.name
  branch     = var.default_branch
  teams      = var.teams
  reviewers  = var.account_type == "organization"
}

module "codeowners" {
  count        = var.account_type == "organization" ? 1 : 0
  source       = "./modules/codeowners"
  organization = var.organization
  repository   = module.repository.name
  branch       = var.default_branch
  owners_file  = "${path.root}/config/owners.yaml"
  teams        = var.teams
  commit       = var.codeowners_commit
}

import {
  for_each = var.import_existing ? toset([var.repository]) : toset([])
  to       = module.repository.github_repository.this
  id       = each.value
}
