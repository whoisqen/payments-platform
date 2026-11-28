locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  central = local.env_cfg.cfg.central
}

terraform {
  source = "${get_repo_root()}/infra/modules//sentry-alerts"
}

# The token comes from SENTRY_AUTH_TOKEN in the environment of the apply role; Sentry is reached through the internal admin gateway.
generate "sentry_provider" {
  path      = "sentry_provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOT
    provider "sentry" {
      base_url = "${trimsuffix(local.central.sentry_url, "/")}/api/"
    }
  EOT
}

# central.sentry_organization and central.sentry_slack_workspace_id (the integration id of the Slack workspace) come from config/platform.yaml.
inputs = {
  organization       = try(local.central.sentry_organization, "payments")
  slack_workspace_id = try(local.central.sentry_slack_workspace_id, "REPLACE_SENTRY_SLACK_WORKSPACE_ID")
  slack_channel      = local.central.sentry_slack_channel
}
