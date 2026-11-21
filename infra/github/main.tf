module "organization" {
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
  source          = "./modules/rulesets"
  repository      = module.repository.name
  required_checks = var.required_checks
  approvals       = var.main_approvals
  tagging_app_id  = var.tagging_app_id
}

module "environments" {
  source     = "./modules/environments"
  repository = module.repository.name
  branch     = var.default_branch
  teams      = var.teams
}

module "codeowners" {
  source       = "./modules/codeowners"
  organization = var.organization
  repository   = module.repository.name
  branch       = var.default_branch
  owners_file  = "${path.root}/config/owners.yaml"
  teams        = var.teams
  commit       = var.codeowners_commit
}
