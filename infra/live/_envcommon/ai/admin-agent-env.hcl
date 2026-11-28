# The read-only role the admin AI agent uses in this environment; every value comes from config/admin-agent.yaml and config/platform.yaml
locals {
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals
  cfg     = local.env_cfg.cfg
  agent   = yamldecode(file("${get_repo_root()}/config/admin-agent.yaml")).environments[local.env_cfg.environment]
  ss      = local.cfg.accounts.shared_services
}

terraform {
  source = "${get_repo_root()}/infra/modules//admin-agent-env"
}

inputs = {
  name_prefix              = local.cfg.naming.prefix
  environment              = local.env_cfg.environment
  account_id               = local.env_cfg.account_id
  region                   = local.cfg.regions.working
  admin_role_arn           = "arn:aws:iam::${local.ss}:role/${local.cfg.naming.prefix}-shared-bedrock-admin-agent"
  opensearch_domain_arn    = "arn:aws:es:${local.cfg.regions.working}:${local.ss}:domain/${local.cfg.central.opensearch.domain_name}"
  log_group_names          = local.agent.log_groups
  clusters                 = { (element(split("/", local.agent.kube_cluster_arn), 1)) = { namespaces = local.agent.namespaces } }
  permissions_boundary_arn = local.env_cfg.permissions_boundary_arn
  tags = {
    team        = "platform"
    owner       = local.env_cfg.owner
    pci-scope   = "connected"
    data-class  = "internal"
    backup-tier = "none"
  }
}
