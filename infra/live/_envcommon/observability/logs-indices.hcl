locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  cfg     = local.env_cfg.cfg
  groups  = local.cfg.access.grafana_groups
  agent   = yamldecode(file("${get_repo_root()}/config/admin-agent.yaml"))
}

terraform {
  source = "${get_repo_root()}/infra/modules//opensearch-indices"
}

# The Dashboards roles reuse the identity provider groups of Grafana; the admin agent role of each environment reads only its own stream.
inputs = {
  environments         = ["dev", "stage", "prod", "shared-services"]
  master_user_arn      = "arn:aws:iam::${local.env_cfg.account_id}:role/${local.cfg.naming.prefix}-${local.env_cfg.environment}-tf-exec"
  groups               = { admin = local.groups.admin, sre = local.groups.sre, security = local.groups.security, engineering = local.groups.engineering }
  env_reader_role_arns = { for env, e in local.agent.environments : env => e.role_arn if contains(["dev", "stage", "prod"], env) }
}
