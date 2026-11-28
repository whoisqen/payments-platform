locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  review  = yamldecode(file("${get_repo_root()}/config/ai-review.yaml"))
  ai      = try(local.env_cfg.cfg.ai, {})
}

terraform {
  source = "${get_repo_root()}/infra/modules//bedrock-access"
}

# Model, region and role name come from config; the admin lists (principals, models, log groups) stay empty until the owner fills ai.* in config/platform.yaml. cde_account_ids and budget_subscriber_emails are required and have no try(): a missing key fails loudly.
inputs = {
  name_prefix                   = local.env_cfg.cfg.naming.prefix
  account_id                    = local.env_cfg.account_id
  region                        = local.review.model.region
  inference_profile_id          = local.review.model.id
  profile_regions               = try(local.ai.profile_regions, [local.review.model.region])
  review_role_name              = local.ai.review_role_name
  github_repository             = local.env_cfg.github_repository
  github_oidc_provider_arn      = local.env_cfg.github_oidc_provider_arn
  permissions_boundary_arn      = local.env_cfg.permissions_boundary_arn
  admin_principal_arns          = try(local.ai.admin_principal_arns, [])
  admin_allowed_model_arns      = try(local.ai.admin_allowed_model_arns, [])
  admin_log_group_names         = try(local.ai.admin_log_group_names, [])
  # The read-only roles of admin-agent-env, the only roles the admin agent may assume (role_arn of config/admin-agent.yaml)
  environment_role_arns = [for e in values(yamldecode(file("${get_repo_root()}/config/admin-agent.yaml")).environments) : e.role_arn]
  cde_account_ids               = local.ai.cde_account_ids
  review_github_environment     = try(local.ai.review_github_environment, "ai-review")
  budget_monthly_usd            = try(local.ai.budget_monthly_usd, 200)
  budget_subscriber_emails      = local.ai.budget_subscriber_emails
  budget_sns_topic_arns         = try(local.ai.budget_sns_topic_arns, [])
  alarm_sns_topic_arns          = try(local.ai.alarm_sns_topic_arns, [])
  cde_logs_allowed              = false
  invocation_logging_enabled    = false
  invocation_log_retention_days = 30
  tags = {
    team        = "platform"
    owner       = local.env_cfg.owner
    pci-scope   = "out-of-scope"
    data-class  = "internal"
    backup-tier = "none"
  }
}
